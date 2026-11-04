# Local development helpers only.
#
# The shipped image is built by Konflux from Containerfile.operator; nothing in
# this file participates in the product build. These targets exist so changes to
# the pinned submodule can be smoke-tested against a real cluster before bumping it.

IMAGE ?= localhost/kube-rbac-proxy:local
KIND_CLUSTER ?= kube-rbac-proxy
NAMESPACE ?= krp-demo

.PHONY: help
help: ## Show this help.
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: image
image: ## Build the proxy image locally from the submodule.
	docker build -f Dockerfile.local -t $(IMAGE) .

.PHONY: kind-up
kind-up: ## Create the kind cluster.
	kind create cluster --config local/kind-config.yaml

.PHONY: kind-load
kind-load: ## Load the locally built image into the kind cluster.
	kind load docker-image $(IMAGE) --name $(KIND_CLUSTER)

.PHONY: deploy
deploy: ## Deploy Prometheus and Alertmanager, each behind a kube-rbac-proxy sidecar.
	kubectl apply -f local/manifests/00-namespace.yaml
	kubectl apply -f local/manifests/01-rbac.yaml
	NAMESPACE=$(NAMESPACE) ./local/setup-secrets.sh
	kubectl apply -f local/manifests/02-prometheus.yaml
	kubectl apply -f local/manifests/03-alertmanager.yaml
	kubectl apply -f local/manifests/04-clients.yaml
	kubectl wait --for=condition=Available --timeout=180s \
		-n $(NAMESPACE) deployment/prometheus deployment/alertmanager
	kubectl wait --for=condition=Ready --timeout=180s \
		-n $(NAMESPACE) pod -l app=krp-demo-client

.PHONY: test
test: ## Run the authorization checks against the deployed proxies.
	NAMESPACE=$(NAMESPACE) ./local/test.sh

.PHONY: demo
demo: image kind-up kind-load deploy ## Build, create the cluster, deploy, then wait for the first scrape.
	@echo
	@echo "Waiting 30s for Prometheus to scrape Alertmanager through the proxy..."
	@sleep 30
	@$(MAKE) test

.PHONY: logs
logs: ## Tail both kube-rbac-proxy sidecars.
	kubectl logs -n $(NAMESPACE) -l app=alertmanager -c kube-rbac-proxy --tail=50
	kubectl logs -n $(NAMESPACE) -l app=prometheus -c kube-rbac-proxy --tail=50

.PHONY: kind-down
kind-down: ## Delete the kind cluster.
	kind delete cluster --name $(KIND_CLUSTER)
