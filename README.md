# kube-rbac-proxy

Builds the `kube-rbac-proxy` image shipped with ACM and MCE. The code is imported
using a submodule which the Containerfile uses as a source for the build.

This repository no longer carries a fork of the proxy source. It tracks
[openshift/kube-rbac-proxy](https://github.com/openshift/kube-rbac-proxy) via the
`openshift-kube-rbac-proxy` submodule, pinned to the `release-5.1` branch.

To update to a new version of kube-rbac-proxy, simply bump the submodule reference:

```sh
git submodule update --remote openshift-kube-rbac-proxy
git add openshift-kube-rbac-proxy
git commit -s -m "Update submodule to <version>"
```

To build against a different OpenShift release line, change `branch` in
`.gitmodules` and re-run the above.

## Trying a change locally

`make demo` builds the image from the submodule with `Dockerfile.local` and runs
it in kind in front of a Prometheus and an Alertmanager, wired the same way MCO
wires them, then asserts the authorization behaviour. See [local/README.md](local/README.md).

## Notes for the build pipeline

The upstream repository commits its `vendor/` directory, so the build is already
offline. The Konflux `prefetch-input` parameter must point at the submodule rather
than the repository root:

```yaml
- name: prefetch-input
  value: '{"type": "gomod", "path": "openshift-kube-rbac-proxy/."}'
```

`IMAGE_NAME` and `CPE_LABEL` stay as build args, supplied per product (ACM and MCE
ship this image under different names and CPEs).

## Consumers

The resulting image is consumed by
[multicluster-observability-operator](https://github.com/stolostron/multicluster-observability-operator)
as a sidecar in front of metrics endpoints (Alertmanager, the MCOA addon manager,
kube-state-metrics, node-exporter) and as the authorization gate in front of the
managed-cluster Prometheus API.
