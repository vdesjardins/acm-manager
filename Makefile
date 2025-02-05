
# Image URL to use all building/pushing image targets
IMG ?= docker.io/vdesjardins/acm-manager:latest
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.31.0


## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUBECTL ?= kubectl
APPLYCONFIGURATION_GEN ?= $(LOCALBIN)/applyconfiguration-gen
CLIENT_GEN ?= $(LOCALBIN)/client-gen
KUSTOMIZE ?= kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = bash
.SHELLFLAGS = -ec -o pipefail
.DELETE_ON_ERROR:
.SUFFIXES:
.ONESHELL:

.PHONY: all
all: build

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUBECTL ?= kubectl
APPLYCONFIGURATION_GEN ?= $(LOCALBIN)/applyconfiguration-gen
CLIENT_GEN ?= $(LOCALBIN)/client-gen
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest

## Tool Versions
KUSTOMIZE_VERSION ?= v5.5.0
CODE_GENERATOR_VERSION ?= v0.32.1
CONTROLLER_TOOLS_VERSION ?= v0.16.4

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases
	$(KUSTOMIZE) build config/crd > ./charts/acm-manager/crds/crds.yaml

.PHONY: generate
generate: controller-gen k8s-client-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

GO_MODULE = $(shell go list -m)
API_DIRS = $(shell find pkg/apis -mindepth 2 -type d | sed "s|^|$(shell go list -m)/|" | paste -sd ",")
.PHONY: k8s-client-gen
k8s-client-gen: client-gen applyconfiguration-gen
	rm -rf pkg/client/{applyconfiguration,versioned}
	@echo ">> generating pkg/client/applyconfiguration..."
	$(APPLYCONFIGURATION_GEN) \
		--go-header-file 	hack/boilerplate.go.txt \
		--input-dirs		"$(API_DIRS)" \
		--output-package  	"$(GO_MODULE)/pkg/client/applyconfiguration" \
		--trim-path-prefix 	"$(GO_MODULE)" \
		--output-base    	"."
	@echo ">> generating pkg/client/versioned..."
	$(CLIENT_GEN) \
		--go-header-file 	          hack/boilerplate.go.txt \
		--input-base                  "" \
		--apply-configuration-package "$(GO_MODULE)/pkg/client/applyconfiguration" \
		--clientset-name              "versioned" \
		--input                       "$(API_DIRS)" \
		--output-package              "$(GO_MODULE)/pkg/client" \
		--trim-path-prefix 	          "$(GO_MODULE)" \
		--output-base                 "."
.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" go test ./... -coverprofile cover.out

##@ Build

.PHONY: build
build: generate fmt vet ## Build manager binary.
	go build -o bin/manager main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./main.go

.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	docker build -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	docker push ${IMG}

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: applyconfiguration-gen
applyconfiguration-gen: $(APPLYCONFIGURATION_GEN) ## Download applyconfiguration-gen locally if necessary.
$(APPLYCONFIGURATION_GEN): $(LOCALBIN)
	# FIXME: applyconfiguration-gen does not currently support any flag for obtaining version
	test -s $(LOCALBIN)/applyconfiguration-gen || \
	GOBIN=$(LOCALBIN) go install k8s.io/code-generator/cmd/applyconfiguration-gen@$(CODE_GENERATOR_VERSION)

.PHONY: client-gen
client-gen: $(CLIENT_GEN) ## Download client-gen locally if necessary.
$(CLIENT_GEN): $(LOCALBIN)
	# FIXME: client-gen does not currently support any flag for obtaining version
	test -s $(LOCALBIN)/client-gen || \
	GOBIN=$(LOCALBIN) go install k8s.io/code-generator/cmd/client-gen@$(CODE_GENERATOR_VERSION)

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary. If wrong version is installed, it will be removed before downloading.
$(KUSTOMIZE): $(LOCALBIN)
	@if test -x $(LOCALBIN)/kustomize && ! $(LOCALBIN)/kustomize version | grep -q $(KUSTOMIZE_VERSION); then \
		echo "$(LOCALBIN)/kustomize version is not expected $(KUSTOMIZE_VERSION). Removing it before installing."; \
		rm -rf $(LOCALBIN)/kustomize; \
	fi
	test -s $(LOCALBIN)/kustomize || GOBIN=$(LOCALBIN) GO111MODULE=on go install sigs.k8s.io/kustomize/kustomize/v5@$(KUSTOMIZE_VERSION)

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary. If wrong version is installed, it will be overwritten.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen && $(LOCALBIN)/controller-gen --version | grep -q $(CONTROLLER_TOOLS_VERSION) || \
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: envtest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	test -s $(LOCALBIN)/setup-envtest || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

# ==================================
# E2E testing
# ==================================

K8S_CLUSTER_NAME := acm-manager
CERT_MANAGER_VERSION ?= 1.16.2

REGISTRY_NAME := "kind-registry"
REGISTRY_PORT := 5000
LOCAL_IMAGE := "localhost:${REGISTRY_PORT}/acm-manager"
NAMESPACE := acm-manager
SERVICE_ACCOUNT := ${NAMESPACE}-sa
export TEST_KUBECONFIG_LOCATION := /tmp/acm_manager_kubeconfig

AWS_ACCOUNT := $(shell aws sts get-caller-identity | jq '.Account' -Mr)
ifndef AWS_ACCOUNT
$(error AWS account could not be retrieved)
endif

OIDC_ACM_MANAGER_IAM_ROLE := arn:aws:iam::${AWS_ACCOUNT}:role/acm-manager
OIDC_EXTERNAL_DNS_IAM_ROLE := arn:aws:iam::${AWS_ACCOUNT}:role/external-dns

OIDC_S3_BUCKET_NAME ?= acm-manager-test

.PHONY: setup-aws
setup-aws: ## setup AWS for IRSA
	if [[ -z "$$OIDC_S3_BUCKET_NAME" ]]; then
		echo "OIDC_S3_BUCKET_NAME variable must be set"
		exit 1
	fi
	./e2e/aws_config/setup.sh $$OIDC_S3_BUCKET_NAME

.PHONY: cleanup-aws
cleanup-aws: ## cleanup AWS for IRSA
	if [[ -z "$$OIDC_S3_BUCKET_NAME" ]]; then
		echo "OIDC_S3_BUCKET_NAME variable must be set"
		exit 1
	fi
	./e2e/aws_config/cleanup.sh $$OIDC_S3_BUCKET_NAME

create-local-registry:
	RUNNING=$$(docker inspect -f '{{.State.Running}}' ${REGISTRY_NAME} 2>/dev/null || true); \
	if [ "$$RUNNING" != 'true' ]; then \
		docker run -d --restart=always -p "127.0.0.1:${REGISTRY_PORT}:5000" --name ${REGISTRY_NAME} registry:2; \
	fi; \
	sleep 15

docker-push-local:
	docker tag ${IMG} ${LOCAL_IMAGE}
	docker push ${LOCAL_IMAGE}

.PHONY: kind-cluster
kind-cluster: ## Use Kind to create a Kubernetes cluster for E2E tests
	if [[ -z "$$OIDC_S3_BUCKET_NAME" ]]; then \
		echo "OIDC_S3_BUCKET_NAME variable not set"; \
		exit 1; \
	fi; \
	if [[ -z "$$AWS_REGION" ]]; then \
		echo "AWS_REGION variable not set"; \
		exit 1; \
	fi; \

	cat e2e/kind_config/config.yaml | sed "s/S3_BUCKET_NAME_PLACEHOLDER/$$OIDC_S3_BUCKET_NAME/g" \
		| sed "s/AWS_REGION_PLACEHOLDER/$$AWS_REGION/g" > /tmp/config.yaml; \
	kind get clusters | grep ${K8S_CLUSTER_NAME} || \
	kind create cluster --name ${K8S_CLUSTER_NAME} --config=/tmp/config.yaml
	kind get kubeconfig --name ${K8S_CLUSTER_NAME} > ${TEST_KUBECONFIG_LOCATION}
	docker network connect "kind" ${REGISTRY_NAME} || true
	kubectl apply -f e2e/kind_config/registry_configmap.yaml --kubeconfig=${TEST_KUBECONFIG_LOCATION}

.PHONY: setup-eks-webhook
setup-eks-webhook:
	#Ensure that there is a OIDC role and S3 bucket available
	if [[ -z "$$OIDC_S3_BUCKET_NAME" ]]; then \
		echo "OIDC_S3_BUCKET_NAME env var is not set"; \
		exit 1; \
	fi;
	#Get open id configuration from API server
	 kubectl apply -f e2e/kind_config/unauth_role.yaml --kubeconfig=${TEST_KUBECONFIG_LOCATION};
	 APISERVER=$$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' --kubeconfig=${TEST_KUBECONFIG_LOCATION});
	 TOKEN=$$(kubectl get secret $$(kubectl get serviceaccount default -o jsonpath='{.secrets[0].name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}) \
	-o jsonpath='{.data.token}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | base64 --decode );
	curl $$APISERVER/.well-known/openid-configuration --header "Authorization: Bearer $$TOKEN" --insecure -o openid-configuration;
	curl $$APISERVER/openid/v1/jwks --header "Authorization: Bearer $$TOKEN" --insecure -o jwks;
	#Put idP configuration in public S3 bucket
	aws s3 cp jwks s3://$$OIDC_S3_BUCKET_NAME/cluster/acm-cluster/openid/v1/jwks;
	aws s3 cp openid-configuration s3://$$OIDC_S3_BUCKET_NAME/cluster/acm-cluster/.well-known/openid-configuration;
	sleep 60;
	envsubst -no-empty -i e2e/kind_config/install_eks.yaml | kubectl apply -f - --kubeconfig=${TEST_KUBECONFIG_LOCATION};
	kubectl wait --for=condition=Available --timeout 300s deployment pod-identity-webhook --kubeconfig=${TEST_KUBECONFIG_LOCATION};

.PHONY: kind-cluster-delete
kind-cluster-delete:
	kind delete cluster --name ${K8S_CLUSTER_NAME}

.PHONY: kind-export-logs
kind-export-logs:
	kind export logs --name ${K8S_CLUSTER_NAME} ${E2E_ARTIFACTS_DIRECTORY}

.PHONY: deploy-cert-manager
deploy-cert-manager: ## Deploy cert-manager in the configured K8s cluster
	kubectl apply --filename=https://github.com/jetstack/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml --kubeconfig=${TEST_KUBECONFIG_LOCATION}
	kubectl wait --for=condition=Available --timeout=300s apiservice v1.cert-manager.io --kubeconfig=${TEST_KUBECONFIG_LOCATION}

.PHONY: deploy-external-dns
deploy-external-dns: ## Deploy External-DNS controller to the K8s cluster
	$(KUSTOMIZE) build config/contrib/external-dns | kubectl apply -f - --kubeconfig=${TEST_KUBECONFIG_LOCATION}
	kubectl annotate serviceaccount external-dns -n external-dns eks.amazonaws.com/role-arn="${OIDC_EXTERNAL_DNS_IAM_ROLE}" --kubeconfig=${TEST_KUBECONFIG_LOCATION} --overwrite;
	kubectl wait --for=condition=Available --timeout=300s deployment external-dns --namespace external-dns --kubeconfig=${TEST_KUBECONFIG_LOCATION}

.PHONY: install-local
install-local: kustomize docker-build docker-push-local
	#install plugin from local docker repo
	sleep 15
	#Create namespace and service account
	kubectl get namespace ${NAMESPACE} --kubeconfig=${TEST_KUBECONFIG_LOCATION} || \
	kubectl create namespace ${NAMESPACE} --kubeconfig=${TEST_KUBECONFIG_LOCATION}

	helm install acm-manager ./charts/acm-manager -n ${NAMESPACE} \
	--set serviceAccount.name=${SERVICE_ACCOUNT} \
	--set image.repository=${LOCAL_IMAGE} \
	--set image.tag=latest --set image.pullPolicy=Always \
	--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${OIDC_ACM_MANAGER_IAM_ROLE}"

.PHONY: uninstall-local
uninstall-local:
	helm uninstall acm-manager -n ${NAMESPACE}

.PHONY: upgrade-local
upgrade-local: uninstall-local install-local

.PHONY: cluster
cluster: build create-local-registry kind-cluster deploy-cert-manager setup-eks-webhook deploy-external-dns install-local ## Sets up a kind cluster using the latest commit on the current branch

.PHONY: e2etest
e2etest: ## Run end to end tests
	kind get kubeconfig --name ${K8S_CLUSTER_NAME} > ${TEST_KUBECONFIG_LOCATION}
	go test -v ./e2e/... -coverprofile cover.out

