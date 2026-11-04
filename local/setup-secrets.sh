#!/usr/bin/env bash
#
# Creates the two pieces of TLS material the Alertmanager sidecar needs, which on
# OpenShift would come from cluster operators that do not exist in kind:
#
#   alertmanager-tls-metrics      serving cert, normally issued by the service CA
#                                 operator via a service annotation
#   alertmanager-clientca-metric  the API server's client CA, which MCO copies out
#                                 of kube-system/extension-apiserver-authentication
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-krp-demo}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo ">> generating a self-signed serving certificate for alertmanager.${NAMESPACE}.svc"
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout "${WORKDIR}/tls.key" \
  -out "${WORKDIR}/tls.crt" \
  -subj "/CN=alertmanager.${NAMESPACE}.svc" \
  -addext "subjectAltName=DNS:alertmanager,DNS:alertmanager.${NAMESPACE},DNS:alertmanager.${NAMESPACE}.svc" \
  2>/dev/null

kubectl create secret tls alertmanager-tls-metrics \
  --namespace "${NAMESPACE}" \
  --cert "${WORKDIR}/tls.crt" \
  --key "${WORKDIR}/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">> copying the API server client CA out of kube-system"
if ! kubectl get configmap extension-apiserver-authentication -n kube-system \
  -o jsonpath='{.data.client-ca-file}' >"${WORKDIR}/client-ca-file" 2>/dev/null ||
  [ ! -s "${WORKDIR}/client-ca-file" ]; then
  echo "error: kube-system/extension-apiserver-authentication has no client-ca-file key." >&2
  echo "       The API server must be started with --client-ca-file for this demo." >&2
  exit 1
fi

kubectl create configmap alertmanager-clientca-metric \
  --namespace "${NAMESPACE}" \
  --from-file=client-ca-file="${WORKDIR}/client-ca-file" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">> done"
