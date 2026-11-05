#!/usr/bin/env bash
#
# Exercises the authorization paths of the two kube-rbac-proxy sidecars.
# Each case prints the HTTP status the proxy returned and whether it matched.
#
set -uo pipefail

NAMESPACE="${NAMESPACE:-krp-demo}"
AM="https://alertmanager.${NAMESPACE}.svc:9096"
PROM="https://prometheus.${NAMESPACE}.svc:9091"

failures=0

# request <pod> <url> <expected-code> <description> [--anonymous]
request() {
  local pod="$1" url="$2" want="$3" desc="$4" anon="${5:-}"
  local auth='-H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"'
  [ "${anon}" = "--anonymous" ] && auth=''

  local got
  got="$(kubectl exec -n "${NAMESPACE}" "${pod}" -c curl -- \
    sh -c "curl -sk -o /dev/null -w '%{http_code}' ${auth} '${url}'" 2>/dev/null)"

  if [ "${got}" = "${want}" ]; then
    printf '  ok    %-3s  %s\n' "${got}" "${desc}"
  else
    printf '  FAIL  %-3s  %s (wanted %s)\n' "${got:-???}" "${desc}" "${want}"
    failures=$((failures + 1))
  fi
}

echo
echo "Alertmanager sidecar  (--allow-paths=/metrics, static authz, client CA)"
request client-no-access      "${AM}/metrics" 403 "no RBAC, not the static user -> denied by all three authorizers"
request client-metrics-reader "${AM}/metrics" 200 "RBAC on nonResourceURL /metrics -> allowed by the sar authorizer"
request client-no-access      "${AM}/"        404 "path outside --allow-paths -> rejected before authentication"
request client-no-access      "${AM}/metrics" 401 "no bearer token at all -> unauthenticated" --anonymous

echo
echo "Prometheus sidecar  (no --allow-paths: the whole HTTP API is gated)"
request client-api-reader "${PROM}/federate?match%5B%5D=up" 200 "RBAC on /federate -> allowed, the path MCO's collector uses"
request client-no-access  "${PROM}/federate?match%5B%5D=up" 403 "no RBAC -> denied"
request client-no-access  "${PROM}/metrics"                 403 "no RBAC -> denied, no allow-paths shortcut exists"

# Not a bug in the proxy, but a sharp edge of gating a whole HTTP API by
# non-resource URL: Kubernetes ships a default ClusterRole, system:discovery,
# bound to the system:authenticated group, granting GET on "/api/*". Prometheus
# serves its query API under /api/v1/, so those paths collide and every
# authenticated identity in the cluster is allowed through. /federate and
# /metrics are outside that prefix and stay protected.
request client-no-access "${PROM}/api/v1/query?query=up" 200 "ANY authenticated user -> allowed by default system:discovery RBAC"

echo
echo "Static authorization  (the behaviour the old stolostron fork silently dropped)"
echo "  The prometheus service account has no RBAC for /metrics. If it is scraping"
echo "  Alertmanager through the proxy, it can only be the static config allowing it."
up="$(kubectl exec -n "${NAMESPACE}" client-api-reader -c curl -- sh -c \
  "curl -sk -H \"Authorization: Bearer \$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)\" \
   '${PROM}/api/v1/query?query=up%7Bjob%3D%22alertmanager-via-kube-rbac-proxy%22%7D'" 2>/dev/null)"

if echo "${up}" | grep -q '"value":\[[^]]*"1"\]'; then
  echo "  ok          scrape target is up -> static authorization is in effect"
else
  echo "  FAIL        scrape target is not up"
  echo "              query result: ${up}"
  echo "              (if this is the only failure, give Prometheus ~30s to scrape and retry)"
  failures=$((failures + 1))
fi

echo
if [ "${failures}" -eq 0 ]; then
  echo "all checks passed"
else
  echo "${failures} check(s) failed"
fi
exit "${failures}"
