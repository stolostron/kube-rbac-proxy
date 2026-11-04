# Local kind demo

Builds the proxy from the pinned submodule and runs it in kind in front of a
Prometheus and an Alertmanager, reproducing the two distinct ways
[multicluster-observability-operator](https://github.com/stolostron/multicluster-observability-operator)
uses it. Use this to smoke-test a submodule bump before committing it.

```sh
make demo      # build, create cluster, deploy, test
make kind-down # clean up
```

Or step by step:

```sh
make image      # docker build -f Dockerfile.local
make kind-up
make kind-load
make deploy
make test
make logs
```

`Dockerfile.local` builds the same submodule source as `Containerfile.operator`,
but with public base images and `CGO_ENABLED=0`, so no registry auth is needed and
the binary runs on distroless static. It is not used by the product build.

## What gets deployed

**Alertmanager**, mirroring MCO's `alertmanager-statefulset.yaml`: the sidecar
listens on 9096, proxies `127.0.0.1:9093`, and is locked down with
`--allow-paths=/metrics`, a static authorization config file, a serving
certificate, and `--client-ca-file`.

**Prometheus**, mirroring MCO's `prometheus-resource.yaml`: the sidecar listens on
9091 and proxies the *entire* Prometheus HTTP API with no `--allow-paths` and no
config file, so every request is authorized by SubjectAccessReview against its
non-resource URL. It passes no certificate and relies on the proxy generating a
self-signed one at startup.

Prometheus additionally scrapes Alertmanager *through* its proxy using its own
service account token. That service account has no RBAC for `/metrics`, so the
scrape succeeding is a live proof that static authorization is in effect.

Two things cannot be reproduced in kind and are faked by `setup-secrets.sh`: the
serving certificate (no service CA operator) and the client CA (copied out of
`kube-system/extension-apiserver-authentication`, which is what MCO does anyway).
The OpenShift fork's hardcoded authorizer for
`system:serviceaccount:openshift-monitoring:prometheus-k8s` also cannot be
exercised here, so the static config names a local service account instead.

## What `make test` checks

```
Alertmanager sidecar  (--allow-paths=/metrics, static authz, client CA)
  ok    403  no RBAC, not the static user -> denied by all three authorizers
  ok    200  RBAC on nonResourceURL /metrics -> allowed by the sar authorizer
  ok    404  path outside --allow-paths -> rejected before authentication
  ok    401  no bearer token at all -> unauthenticated

Prometheus sidecar  (no --allow-paths: the whole HTTP API is gated)
  ok    200  RBAC on /federate -> allowed, the path MCO's collector uses
  ok    403  no RBAC -> denied
  ok    403  no RBAC -> denied, no allow-paths shortcut exists
  ok    200  ANY authenticated user -> allowed by default system:discovery RBAC

Static authorization  (the behaviour the old stolostron fork silently dropped)
  ok          scrape target is up -> static authorization is in effect
```

That second-to-last line is not a proxy bug and not something this demo
introduces. Kubernetes' built-in `system:discovery` ClusterRole is bound to the
`system:authenticated` group and grants GET on `/api/*`. Prometheus serves its
query API under `/api/v1/`, so the two URL spaces collide and any authenticated
identity in the cluster can query Prometheus through a proxy configured this way.
`/federate` and `/metrics` are outside the prefix and stay protected. This applies
equally to MCO's managed-cluster Prometheus sidecar, and is identical in the old
and new forks.
