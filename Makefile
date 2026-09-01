# Image URL to use all building/pushing image targets
IMG ?= docker.io/vdesjardins/acm-manager:latest
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.36.2

## Tool Binaries
KUBECTL ?= kubectl
KUSTOMIZE ?= kustomize
CONTROLLER_GEN ?= controller-gen
ENVTEST ?= setup-envtest
HELM ?= helm
KIND ?= kind
CT ?= ct
DOCKER ?= docker
GO ?= go
APPLYCONFIGURATION_GEN ?= applyconfiguration-gen
CLIENT_GEN ?= client-gen

# Calculate Go module name dynamically
GO_MODULE = $(shell $(GO) list -m)

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

.PHONY: setup-aws
setup-aws: ## Setup AWS resources for OIDC
	if [[ -z "$$OIDC_S3_BUCKET_NAME" ]]; then \
		echo "OIDC_S3_BUCKET_NAME variable must be set"; \
		exit 1; \
	fi; \
	AWS_ACCOUNT=$(call get_aws_account); \
	if [[ -z "$$AWS_ACCOUNT" ]]; then \
		echo "AWS account could not be retrieved"; \
		exit 1; \
	fi
	./e2e/aws_config/setup.sh $$OIDC_S3_BUCKET_NAME

##@ Development
.PHONY: manifests
manifests: ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases
	$(KUSTOMIZE) build config/crd > ./charts/acm-manager/crds/crds.yaml

# Fix API directory paths - note the path for API modules should likely match what exists in the repo
API_GROUPS = $(shell find pkg/apis -mindepth 1 -maxdepth 1 -type d -not -path "*/\.*" | xargs -n1 basename)
API_GROUP_VERSIONS = $(shell find pkg/apis -mindepth 2 -maxdepth 2 -type d -not -path "*/\.*" | sed 's|pkg/apis/||' | tr '/' '.')

.PHONY: generate
generate: ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	@echo ">> cleaning old generated files..."
	@rm -rf pkg/client/{applyconfiguration,versioned}
	@echo ">> running k8s-client-gen..."
	@$(MAKE) k8s-client-gen
	@echo ">> running controller-gen..."
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."
	@echo "✅ Code generation completed"

.PHONY: k8s-client-gen
k8s-client-gen:
	rm -rf pkg/client/{applyconfiguration,versioned}
	@echo ">> generating pkg/client/applyconfiguration..."
	@applyconfiguration-gen \
		--go-header-file hack/boilerplate.go.txt \
		--output-dir pkg/client/applyconfiguration \
		--output-pkg "$(GO_MODULE)/pkg/client/applyconfiguration" \
		$(GO_MODULE)/pkg/apis/acmmanager/v1alpha1
	@echo ">> generating pkg/client/versioned..."
	@client-gen \
		--go-header-file hack/boilerplate.go.txt \
		--input-base "" \
		--apply-configuration-package "$(GO_MODULE)/pkg/client/applyconfiguration" \
		--clientset-name "versioned" \
		--input $(GO_MODULE)/pkg/apis/acmmanager/v1alpha1 \
		--output-pkg "$(GO_MODULE)/pkg/client" \
		--output-dir pkg/client

	@echo ">> fixing generated directory names and import paths (Go doesn't allow hyphens in package names)..."
	# Fix import paths in generated code - Go requires valid package identifiers (no hyphens)
	@echo "Fixing import paths in generated files..."
	@find pkg/client -type f -name "*.go" -print | while read file; do \
		echo "Processing $${file}..."; \
		cp "$${file}" "$${file}.tmp"; \
		sed -e 's|acm-manager/v1alpha1|acmmanager/v1alpha1|g' \
		    -e 's|/applyconfiguration/acm-manager/|/applyconfiguration/acmmanager/|g' \
		    -e 's|/typed/acm-manager/|/typed/acmmanager/|g' \
		    -e 's|"$(GO_MODULE)/pkg/client/applyconfiguration/acm-manager|"$(GO_MODULE)/pkg/client/applyconfiguration/acmmanager|g' \
		    -e 's|"$(GO_MODULE)/pkg/client/versioned/typed/acm-manager|"$(GO_MODULE)/pkg/client/versioned/typed/acmmanager|g' \
		    "$${file}.tmp" > "$${file}"; \
		rm "$${file}.tmp"; \
	done

.PHONY: fmt
fmt: ## Run go fmt against code.
	$(GO) fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	@echo "🧹 Cleaning Go cache before vet to ensure version consistency..."
	@$(GO) clean -cache
	@echo "🔍 Running go vet..."
	@$(GO) vet ./...
	@echo "✅ Code vetting completed"

.PHONY: test
test: manifests generate fmt vet ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) -p path)" $(GO) test ./... -coverprofile cover.out

.PHONY: test-unit
test-unit: manifests generate fmt vet ## Run only unit tests (no e2e tests)
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) -p path)" $(GO) test -v ./pkg/... -coverprofile cover.out

##@ Build

.PHONY: clean-go-cache
clean-go-cache: ## Clean Go build and module cache to fix version mismatches
	@echo "🧹 Cleaning Go build cache..."
	@$(GO) clean -cache
	@echo "🧹 Cleaning Go module cache..."
	@$(GO) clean -modcache
	@echo "✅ Go caches cleaned"

.PHONY: build
build: clean-go-cache generate fmt vet ## Build manager binary.
	$(GO) build -o bin/manager main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	$(GO) run ./main.go

.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	$(DOCKER) build -t ${IMG} . --load

.PHONY: docker-push
docker-push: docker-build docker-push-local ## Push docker image with the manager.
	$(DOCKER) push ${IMG}

.PHONY: docker-push-local
docker-push-local:
	@echo "🚀 Pushing image to local registry..."
	$(DOCKER) tag ${IMG} ${LOCAL_IMAGE}
	$(DOCKER) push ${LOCAL_IMAGE} --tls-verify=false
	@echo "✅ Image pushed to local registry successfully"

# PLATFORMS defines the target platforms for the manager image be built to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - be able to use docker buildx. More info: https://docs.docker.com/build/buildx/
# - have enabled BuildKit. More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image to your registry (i.e. if you do not set a valid value via IMG=<myregistry/image:<tag>> then the export will fail)
# To adequately provide solutions that are compatible with multiple platforms, you should consider using this option.
PLATFORMS ?= linux/arm64,linux/amd64,linux/s390x,linux/ppc64le
.PHONY: docker-buildx
docker-buildx: ## Build and push docker image for the manager for cross-platform support
	# copy existing Dockerfile and insert --platform=${BUILDPLATFORM} into Dockerfile.cross, and preserve the original Dockerfile
	sed -e '1 s/\(^FROM\)/FROM --platform=\$$\{BUILDPLATFORM\}/; t' -e ' 1,// s//FROM --platform=\$$\{BUILDPLATFORM\}/' Dockerfile > Dockerfile.cross
	- $(CONTAINER_TOOL) buildx create --name acm-manager-builder
	$(CONTAINER_TOOL) buildx use acm-manager-builder
	- $(CONTAINER_TOOL) buildx build --push --platform=$(PLATFORMS) --tag ${IMG} -f Dockerfile.cross .
	- $(CONTAINER_TOOL) buildx rm acm-manager-builder
	rm Dockerfile.cross

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build | $(KUBECTL) apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: kustomize
kustomize: ## Verify kustomize is available via nix
	@echo ">> checking if kustomize is available..."
	@which $(KUSTOMIZE) > /dev/null 2>&1 || { echo "❌ kustomize not found in PATH. Make sure you're running within the nix shell."; exit 1; }
	@echo "✅ kustomize is ready"

K8S_CLUSTER_NAME := acm-manager
CERT_MANAGER_VERSION ?= v1.21.1
EXTERNAL_DNS_VERSION ?= 1.21.1

REGISTRY_NAME := "kind-registry"
REGISTRY_PORT := 5000
REGISTRY_DIR := /etc/containerd/certs.d/localhost:$(REGISTRY_PORT)
LOCAL_IMAGE := "localhost:${REGISTRY_PORT}/acm-manager"
NAMESPACE := acm-manager
SERVICE_ACCOUNT := ${NAMESPACE}-sa
export TEST_KUBECONFIG_LOCATION := /tmp/acm_manager_kubeconfig

# Helper function to get AWS account ID
define get_aws_account
$(shell aws sts get-caller-identity | jq '.Account' -Mr)
endef

AWS_ACCOUNT := $(call get_aws_account)
ifndef AWS_ACCOUNT
$(warning AWS account could not be retrieved)
endif

OIDC_ACM_MANAGER_IAM_ROLE := arn:aws:iam::$(AWS_ACCOUNT):role/acm-manager
OIDC_EXTERNAL_DNS_IAM_ROLE := arn:aws:iam::$(AWS_ACCOUNT):role/external-dns

OIDC_S3_BUCKET_NAME ?= acm-manager-test

.PHONY: check-env-vars
check-env-vars: ## Check required environment variables
	@echo "🔍 Validating environment variables..."
	@if [ -z "$(OIDC_S3_BUCKET_NAME)" ] || [ -z "$(AWS_REGION)" ]; then \
		echo "❌ Required environment variables OIDC_S3_BUCKET_NAME and AWS_REGION must be set"; \
		exit 1; \
	fi
	@echo "✅ Environment variables are set correctly"

.PHONY: deploy-external-dns
deploy-external-dns: ## Deploy external-dns
	@echo "🚀 Deploying external-dns..."
	@echo "⏳ Ensuring pod-identity-webhook is ready before external-dns deployment..."
	@echo "🔍 Waiting for pod-identity-webhook deployment to be ready..."
	@if ! kubectl rollout status deployment/pod-identity-webhook -n default --timeout=120s --kubeconfig=${TEST_KUBECONFIG_LOCATION}; then \
		echo "❌ pod-identity-webhook deployment failed to become ready"; \
		exit 1; \
	fi
	@echo "🔍 Waiting for MutatingWebhookConfiguration to be active..."
	@for i in {1..12}; do \
		echo "Checking MutatingWebhookConfiguration (attempt $$i/12)..."; \
		if kubectl get mutatingwebhookconfiguration pod-identity-webhook --kubeconfig=${TEST_KUBECONFIG_LOCATION} >/dev/null 2>&1; then \
			echo "✅ MutatingWebhookConfiguration is active"; \
			break; \
		fi; \
		if [ "$$i" = "12" ]; then \
			echo "❌ MutatingWebhookConfiguration failed to become active"; \
			exit 1; \
		fi; \
		echo "Waiting for MutatingWebhookConfiguration (attempt $$i/12)..."; \
		sleep 5; \
	done
	@echo "✅ pod-identity-webhook is fully ready, proceeding with external-dns deployment..."
	@if ! $(HELM) repo add external-dns https://kubernetes-sigs.github.io/external-dns/ --force-update; then \
		echo "❌ Failed to add external-dns Helm repository"; \
		exit 1; \
	fi
	@if ! $(HELM) repo update; then \
		echo "❌ Failed to update Helm repositories"; \
		exit 1; \
	fi
	@echo "📦 Installing externa-dns with CRDs..."
	@if ! $(HELM) upgrade --install external-dns external-dns/external-dns \
		--namespace external-dns \
		--create-namespace \
		--version ${EXTERNAL_DNS_VERSION} \
		--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::$(AWS_ACCOUNT):role/external-dns" \
		--set sources="{ingress,service,crd}" \
		--kubeconfig=${TEST_KUBECONFIG_LOCATION} \
		--wait --timeout=180s; then \
		echo "❌ Failed to install external-dns via Helm"; \
		$(HELM) status external-dns -n external-dns --kubeconfig=${TEST_KUBECONFIG_LOCATION}; \
		exit 1; \
	fi

.PHONY: validate-external-dns-oidc
validate-external-dns-oidc: ## Validate external-dns pod has proper OIDC injection with retry logic
	@echo "🔍 Validating pod-identity-webhook AWS configuration injection for external-dns..."
	@VALIDATION_RETRIES=3; \
	RETRY_COUNT=0; \
	while [ $$RETRY_COUNT -lt $$VALIDATION_RETRIES ]; do \
		echo "📋 Validation attempt $$(($$RETRY_COUNT + 1))/$$VALIDATION_RETRIES"; \
		if $(MAKE) validate-external-dns-oidc-attempt; then \
			echo "✅ external-dns AWS configuration validation completed successfully"; \
			exit 0; \
		else \
			RETRY_COUNT=$$(($$RETRY_COUNT + 1)); \
			if [ $$RETRY_COUNT -lt $$VALIDATION_RETRIES ]; then \
				echo "⚠️ Validation failed, attempting pod restart and retry..."; \
				echo "🔄 Restarting external-dns deployment to trigger re-injection..."; \
				kubectl rollout restart deployment/external-dns -n default --kubeconfig=${TEST_KUBECONFIG_LOCATION}; \
				echo "⏳ Waiting for restarted pod to be ready..."; \
				kubectl rollout status deployment/external-dns -n default --timeout=120s --kubeconfig=${TEST_KUBECONFIG_LOCATION}; \
				sleep 10; \
			else \
				echo "❌ Validation failed after $$VALIDATION_RETRIES attempts"; \
				echo "💡 Check pod-identity-webhook logs: kubectl logs -n default -l app=pod-identity-webhook"; \
				echo "💡 Check external-dns service account: kubectl get sa external-dns -n default -o yaml"; \
				exit 1; \
			fi; \
		fi; \
	done

.PHONY: validate-external-dns-oidc-attempt
validate-external-dns-oidc-attempt: ## Single validation attempt for external-dns OIDC injection
	@echo "⏳ Waiting for external-dns pod to be running..."
	@for i in {1..10}; do \
		if kubectl get pods -n external-dns -l app.kubernetes.io/instance=external-dns -o jsonpath='{.items[0].status.phase}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "Running"; then \
			echo "✅ external-dns pod is running"; \
			break; \
		fi; \
		if [ "$$i" = "10" ]; then \
			echo "❌ external-dns pod failed to reach Running state"; \
			kubectl get pods -n external-dns -l app.kubernetes.io/instance=external-dns --kubeconfig=${TEST_KUBECONFIG_LOCATION}; \
			exit 1; \
		fi; \
		echo "Waiting for external-dns pod (attempt $$i/10)..."; \
		sleep 5; \
	done

	@echo "🔍 Checking AWS IAM role environment variables..."
	@POD_NAME=$$(kubectl get pods -n external-dns -l app.kubernetes.io/instance=external-dns -o jsonpath='{.items[0].metadata.name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}) && \
	if ! kubectl get pods -n external-dns $$POD_NAME -o jsonpath='{.spec.containers[0].env[*].name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "AWS_ROLE_ARN"; then \
		echo "❌ AWS_ROLE_ARN environment variable not found in external-dns pod"; \
		echo "Pod identity webhook might not be working correctly"; \
		exit 1; \
	else \
		AWS_ROLE_ARN=$$(kubectl get pods -n external-dns $$POD_NAME -o jsonpath='{.spec.containers[0].env[?(@.name=="AWS_ROLE_ARN")].value}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}); \
		echo "✅ AWS_ROLE_ARN environment variable properly injected: $$AWS_ROLE_ARN"; \
	fi

	@echo "🔍 Checking AWS web identity token file..."
	@POD_NAME=$$(kubectl get pods -n external-dns -l app.kubernetes.io/instance=external-dns -o jsonpath='{.items[0].metadata.name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}) && \
	if ! kubectl get pods -n external-dns $$POD_NAME -o jsonpath='{.spec.containers[0].env[*].name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "AWS_WEB_IDENTITY_TOKEN_FILE"; then \
		echo "❌ AWS_WEB_IDENTITY_TOKEN_FILE environment variable not found in external-dns pod"; \
		echo "Pod identity webhook might not be working correctly"; \
		exit 1; \
	else \
		TOKEN_FILE=$$(kubectl get pods -n external-dns $$POD_NAME -o jsonpath='{.spec.containers[0].env[?(@.name=="AWS_WEB_IDENTITY_TOKEN_FILE")].value}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}); \
		echo "✅ AWS_WEB_IDENTITY_TOKEN_FILE environment variable properly injected: $$TOKEN_FILE"; \
	fi

	@echo "🔍 Checking AWS_REGION environment variable..."
	@POD_NAME=$$(kubectl get pods -n external-dns -l app.kubernetes.io/instance=external-dns -o jsonpath='{.items[0].metadata.name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}) && \
	if ! kubectl get pods -n external-dns $$POD_NAME -o jsonpath='{.spec.containers[0].env[*].name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "AWS_REGION"; then \
		echo "❌ AWS_REGION environment variable not found in external-dns pod"; \
		exit 1; \
	else \
		AWS_REGION=$$(kubectl get pods -n external-dns $$POD_NAME -o jsonpath='{.spec.containers[0].env[?(@.name=="AWS_REGION")].value}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}); \
		echo "✅ AWS_REGION environment variable properly set: $$AWS_REGION"; \
	fi

	@echo "🔍 Checking for IAM token volume..."
	@POD_NAME=$$(kubectl get pods -n external-dns -l app.kubernetes.io/instance=external-dns -o jsonpath='{.items[0].metadata.name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}) && \
	if ! kubectl get pods -n external-dns $$POD_NAME -o jsonpath='{.spec.volumes[*].name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "aws-iam-token"; then \
		echo "❌ aws-iam-token volume not found in external-dns pod"; \
		echo "Pod identity webhook might not be mounting the token correctly"; \
		exit 1; \
	else \
		echo "✅ aws-iam-token volume properly created"; \
	fi

	@echo "🔍 Checking for IAM token volume mount..."
	@POD_NAME=$$(kubectl get pods -n external-dns -l app.kubernetes.io/instance=external-dns -o jsonpath='{.items[0].metadata.name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}) && \
	if ! kubectl get pods -n external-dns $$POD_NAME -o jsonpath='{.spec.containers[0].volumeMounts[*].name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "aws-iam-token"; then \
		echo "❌ aws-iam-token volume not mounted in external-dns container"; \
		echo "Pod identity webhook might not be mounting the token correctly"; \
		exit 1; \
	else \
		MOUNT_PATH=$$(kubectl get pods -n external-dns $$POD_NAME -o jsonpath='{.spec.containers[0].volumeMounts[?(@.name=="aws-iam-token")].mountPath}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}); \
		echo "✅ aws-iam-token volume properly mounted at path: $$MOUNT_PATH"; \
	fi

.PHONY: kind-cluster
kind-cluster: check-env-vars create-local-registry ## Create a Kind cluster with required configuration
	@echo "🚀 Creating Kind cluster ..."
	@echo "🔧 Preparing Kind configuration..."
	@if $(KIND) get clusters | grep -q "${K8S_CLUSTER_NAME}"; then \
		echo "ℹ️ Kind cluster ${K8S_CLUSTER_NAME} already exists"; \
	else \
		echo "📦 Creating Kind cluster..."; \
		$(KIND) --version
		cat e2e/kind_config/config.yaml | sed "s/S3_BUCKET_NAME_PLACEHOLDER/$$OIDC_S3_BUCKET_NAME/g" | sed "s/AWS_REGION_PLACEHOLDER/$$AWS_REGION/g" | $(KIND) create cluster --verbosity 6 --name=${K8S_CLUSTER_NAME} --config=-; \
		echo "Adding local registry config to cluster nodes"
		for node in $$(kind get nodes --name $(K8S_CLUSTER_NAME)); do \
			echo "Configuring kubernetes node named $$node with local container registry"; \
			$(DOCKER) exec "$$node" mkdir -p "$(REGISTRY_DIR)"; \
			printf '%s\n' '[host."http://'"$(REGISTRY_NAME)"':$(REGISTRY_PORT)"]' | $(DOCKER) exec -i "$$node" sh -c 'cat > "$(REGISTRY_DIR)/hosts.toml"'; \
		done
	fi
	@echo "🔧 Generating kubeconfig..."
	@if ! $(KIND) get kubeconfig --name ${K8S_CLUSTER_NAME} > ${TEST_KUBECONFIG_LOCATION}; then \
		echo "❌ Failed to generate kubeconfig"; \
		exit 1; \
	fi
	@echo "🔗 Connecting registry to Kind network..."
	@if $(DOCKER) network ls | grep -q "kind"; then \
		$(DOCKER) network connect "kind" ${REGISTRY_NAME} 2>/dev/null || echo "ℹ️ Registry already connected to kind network"; \
	else \
		echo "⚠️ Kind network not found, registry connection may fail"; \
	fi
	@echo "🔧 Applying registry configuration..."
	@if ! kubectl apply -f e2e/kind_config/registry_configmap.yaml --kubeconfig=${TEST_KUBECONFIG_LOCATION}; then \
		echo "❌ Failed to apply registry configuration"; \
		exit 1; \
	fi
	@echo "✅ Kind cluster setup completed successfully"

E2E_DIR := $(CURDIR)/e2e

.PHONY: create-local-registry
create-local-registry: ## Create and configure local registry for Kind cluster
	@echo "🚀 Setting up local registry for Kind cluster..."
	@echo "🔍 Checking if registry container already exists..."
	@if $(DOCKER) ps -a --format "table {{.Names}}" | grep -q "^${REGISTRY_NAME}$$"; then \
		echo "ℹ️ Registry container ${REGISTRY_NAME} already exists"; \
		if ! $(DOCKER) ps --format "table {{.Names}}" | grep -q "^${REGISTRY_NAME}$$"; then \
			echo "🔄 Starting existing registry container..."; \
			$(DOCKER) start ${REGISTRY_NAME}; \
		fi; \
	else \
		echo "📦 Creating new registry container..."; \
		if ! $(DOCKER) run -d --restart=always -p "127.0.0.1:${REGISTRY_PORT}:${REGISTRY_PORT}" --name ${REGISTRY_NAME} docker.io/registry:2; then \
			echo "❌ Failed to create registry container"; \
			exit 1; \
		fi; \
	fi
	@echo "🔍 Validating registry health..."
	@for i in {1..12}; do \
		echo "Checking registry health (attempt $$i/12)..."; \
		if curl -f http://127.0.0.1:${REGISTRY_PORT}/v2/ >/dev/null 2>&1; then \
			echo "✅ Registry is healthy and accessible"; \
			break; \
		elif [ "$$i" = "12" ]; then \
			echo "❌ Registry failed to become healthy within 60 seconds"; \
			$(DOCKER) logs ${REGISTRY_NAME} --tail 20; \
			exit 1; \
		else \
			sleep 5; \
		fi; \
	done
	@echo "✅ Local registry setup completed successfully"

.PHONY: setup-eks-webhook
setup-eks-webhook: ## Setup EKS webhook for OIDC on Kind cluster
	@echo "📢 Setting up EKS pod identity webhook..."
	@envsubst <  ./e2e/kind_config/install_eks.yaml >/tmp/install_eks.yaml
	@kubectl apply -f /tmp/install_eks.yaml --kubeconfig=${TEST_KUBECONFIG_LOCATION}
	@echo "⏳ Waiting for pod-identity-webhook deployment to be ready..."
	@kubectl rollout status deployment/pod-identity-webhook -n default --timeout=300s
	@echo "✅ pod-identity-webhook is ready"
	@echo "⏳ Waiting for webhook configuration to be active..."
	@for i in {1..10}; do \
		echo "Checking MutatingWebhookConfiguration (attempt $$i/10)..."; \
		if kubectl get MutatingWebhookConfiguration pod-identity-webhook --kubeconfig=${TEST_KUBECONFIG_LOCATION} >/dev/null 2>&1; then \
			echo "✅ MutatingWebhookConfiguration is active"; \
			break; \
		fi; \
		if [ "$$i" = "10" ]; then \
			echo "❌ MutatingWebhookConfiguration not found after multiple attempts"; \
			exit 1; \
		fi; \
		sleep 3; \
	done

	@echo "🔍 Retrieving API server configuration..."
	@APISERVER=$$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'); \
	TOKEN=$$(kubectl get secret $$(kubectl get serviceaccount default -o jsonpath='{.secrets[0].name}') \
	-o jsonpath='{.data.token}' | base64 --decode ); \
	echo "📥 Downloading OIDC configuration from API server..."; \
	if ! curl $$APISERVER/.well-known/openid-configuration --header "Authorization: Bearer $$TOKEN" --insecure -o openid-configuration --fail --silent --show-error; then \
		echo "❌ Failed to download openid-configuration"; \
		exit 1; \
	fi; \
	if ! curl $$APISERVER/openid/v1/jwks --header "Authorization: Bearer $$TOKEN" --insecure -o jwks --fail --silent --show-error; then \
		echo "❌ Failed to download jwks"; \
		exit 1; \
	fi

	@echo "☁️ Uploading OIDC configuration to S3..."
	@if ! aws s3 cp jwks s3://$$OIDC_S3_BUCKET_NAME/cluster/acm-cluster/openid/v1/jwks; then \
		echo "❌ Failed to upload jwks to S3"; \
		exit 1; \
	fi
	@if ! aws s3 cp openid-configuration s3://$$OIDC_S3_BUCKET_NAME/cluster/acm-cluster/.well-known/openid-configuration; then \
		echo "❌ Failed to upload openid-configuration to S3"; \
		exit 1; \
	fi
	@$(SHELL) ./e2e/aws_config/setup.sh "$$OIDC_S3_BUCKET_NAME" "$$TEST_DOMAIN_NAME" configure_oidc "$$OIDC_S3_BUCKET_NAME" "$$AWS_REGION"
	@echo "🔍 Validating S3 objects exist..."
	@for i in {1..6}; do \
		echo "Checking S3 object existence (attempt $$i/6)..."; \
		if aws s3 ls s3://$$OIDC_S3_BUCKET_NAME/cluster/acm-cluster/openid/v1/jwks >/dev/null 2>&1 && \
		   aws s3 ls s3://$$OIDC_S3_BUCKET_NAME/cluster/acm-cluster/.well-known/openid-configuration >/dev/null 2>&1; then \
			echo "✅ S3 objects exist and are accessible via AWS CLI"; \
			break; \
		elif [ "$$i" = "6" ]; then \
			echo "❌ S3 objects failed to be found within 30 seconds"; \
			echo "Check S3 upload and bucket configuration"; \
			exit 1; \
		else \
			sleep 5; \
		fi; \
	done
	@echo "✅ EKS webhook setup completed successfully"

.PHONY: deploy-prometheus-crds
deploy-prometheus-crds: ## Deploy Prometheus Operator CRDs for monitoring
	@echo "🔧 Installing Prometheus Operator CRDs..."
	@$(KUBECTL) apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.68.0/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml --kubeconfig=${TEST_KUBECONFIG_LOCATION}
	@echo "✅ Prometheus Operator CRDs installed"

.PHONY: deploy-cert-manager
deploy-cert-manager: ## Deploy cert-manager to the K8s cluster
	@echo "🚀 Deploying cert-manager..."
	@if ! $(HELM) repo add jetstack https://charts.jetstack.io --force-update; then \
		echo "❌ Failed to add jetstack Helm repository"; \
		exit 1; \
	fi
	@if ! $(HELM) repo update; then \
		echo "❌ Failed to update Helm repositories"; \
		exit 1; \
	fi
	@echo "📦 Installing cert-manager with CRDs..."
	@if ! $(HELM) upgrade --install cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--version ${CERT_MANAGER_VERSION} \
		--set crds.enabled=true \
		--kubeconfig=${TEST_KUBECONFIG_LOCATION} \
		--wait --timeout=180s; then \
		echo "❌ Failed to install cert-manager via Helm"; \
		$(HELM) status cert-manager -n cert-manager --kubeconfig=${TEST_KUBECONFIG_LOCATION}; \
		exit 1; \
	fi
	@echo "🔍 Validating cert-manager deployment..."
	@for i in {1..12}; do \
		echo "Checking cert-manager pods (attempt $$i/12)..."; \
		if kubectl get pods -n cert-manager --kubeconfig=${TEST_KUBECONFIG_LOCATION} --field-selector=status.phase=Running | grep -q "cert-manager"; then \
			echo "✅ All cert-manager pods are running"; \
			break; \
		elif [ "$$i" = "12" ]; then \
			echo "❌ cert-manager pods failed to start within 60 seconds"; \
			kubectl get pods -n cert-manager --kubeconfig=${TEST_KUBECONFIG_LOCATION}; \
			kubectl describe pods -n cert-manager --kubeconfig=${TEST_KUBECONFIG_LOCATION}; \
			exit 1; \
		else \
			sleep 5; \
		fi; \
	done
	@echo "🔍 Validating cert-manager API availability..."
	@for i in {1..6}; do \
		echo "Checking cert-manager API (attempt $$i/6)..."; \
		if kubectl get apiservice v1.cert-manager.io --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "True"; then \
			echo "✅ cert-manager API is available"; \
			break; \
		elif [ "$$i" = "6" ]; then \
			echo "❌ cert-manager API failed to become available within 30 seconds"; \
			kubectl get apiservice v1.cert-manager.io --kubeconfig=${TEST_KUBECONFIG_LOCATION}; \
			exit 1; \
		else \
			sleep 5; \
		fi; \
	done
	@echo "✅ cert-manager deployment completed successfully"

.PHONY: install-acm-manager-local
install-acm-manager-local: kustomize docker-build docker-push-local deploy-prometheus-crds
	@echo "🚀 Installing ACM manager from local registry..."
	@echo "🔍 Validating local registry accessibility..."
	@for i in {1..6}; do \
		echo "Checking local registry (attempt $$i/6)..."; \
		if curl -f http://127.0.0.1:${REGISTRY_PORT}/v2/ >/dev/null 2>&1; then \
			echo "✅ Local registry is accessible"; \
			break; \
		elif [ "$$i" = "6" ]; then \
			echo "❌ Local registry is not accessible after 30 seconds"; \
			exit 1; \
		else \
			sleep 5; \
		fi; \
	done
	@echo "🔧 Creating namespace and service account..."
	@kubectl get namespace ${NAMESPACE} --kubeconfig=${TEST_KUBECONFIG_LOCATION} || \
	kubectl create namespace ${NAMESPACE} --kubeconfig=${TEST_KUBECONFIG_LOCATION}
	@echo "🚀 Installing ACM manager with Helm..."
	@$(HELM) upgrade --install acm-manager ./charts/acm-manager -n ${NAMESPACE} \
	--set serviceAccount.name=${SERVICE_ACCOUNT} \
	--set image.repository=${LOCAL_IMAGE} \
	--set image.tag=latest --set image.pullPolicy=Always \
	--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${OIDC_ACM_MANAGER_IAM_ROLE}"
	@echo "🔍 Waiting for ACM manager deployment to be ready..."
	@kubectl wait --for=condition=available --timeout=90s deployment/acm-manager -n ${NAMESPACE} --kubeconfig=${TEST_KUBECONFIG_LOCATION} || \
		echo "⚠️ Timed out waiting for ACM manager deployment - continuing anyway"
	@echo "✅ ACM manager installation completed"

	@echo "🔍 Validating pod-identity-webhook AWS configuration injection..."
	@echo "⏳ Waiting for acm-manager pod to be running..."
	@for i in {1..10}; do \
		if kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=acm-manager -o jsonpath='{.items[0].status.phase}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "Running"; then \
			echo "✅ acm-manager pod is running"; \
			break; \
		fi; \
		if [ "$$i" = "10" ]; then \
			echo "❌ acm-manager pod failed to reach Running state"; \
			kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=acm-manager --kubeconfig=${TEST_KUBECONFIG_LOCATION}; \
			exit 1; \
		fi; \
		echo "Waiting for acm-manager pod (attempt $$i/10)..."; \
		sleep 5; \
	done

	@echo "🔍 Checking AWS IAM role environment variables..."
	@POD_NAME=$$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=acm-manager -o jsonpath='{.items[0].metadata.name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}) && \
	if ! kubectl get pods -n ${NAMESPACE} $$POD_NAME -o jsonpath='{.spec.containers[0].env[*].name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "AWS_ROLE_ARN"; then \
		echo "❌ AWS_ROLE_ARN environment variable not found in acm-manager pod"; \
		echo "Pod identity webhook might not be working correctly"; \
		kubectl get pods -n ${NAMESPACE} $$POD_NAME -o yaml --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -A 20 "env:"; \
		exit 1; \
	else \
		AWS_ROLE_ARN=$$(kubectl get pods -n ${NAMESPACE} $$POD_NAME -o jsonpath='{.spec.containers[0].env[?(@.name=="AWS_ROLE_ARN")].value}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}); \
		echo "✅ AWS_ROLE_ARN environment variable properly injected: $$AWS_ROLE_ARN"; \
	fi

	@echo "🔍 Checking AWS web identity token file..."
	@POD_NAME=$$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=acm-manager -o jsonpath='{.items[0].metadata.name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}) && \
	if ! kubectl get pods -n ${NAMESPACE} $$POD_NAME -o jsonpath='{.spec.containers[0].env[*].name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "AWS_WEB_IDENTITY_TOKEN_FILE"; then \
		echo "❌ AWS_WEB_IDENTITY_TOKEN_FILE environment variable not found in acm-manager pod"; \
		echo "Pod identity webhook might not be working correctly"; \
		kubectl get pods -n ${NAMESPACE} $$POD_NAME -o yaml --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -A 20 "env:"; \
		exit 1; \
	else \
		TOKEN_FILE=$$(kubectl get pods -n ${NAMESPACE} $$POD_NAME -o jsonpath='{.spec.containers[0].env[?(@.name=="AWS_WEB_IDENTITY_TOKEN_FILE")].value}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}); \
		echo "✅ AWS_WEB_IDENTITY_TOKEN_FILE environment variable properly injected: $$TOKEN_FILE"; \
	fi

	@echo "🔍 Checking for IAM token volume..."
	@POD_NAME=$$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=acm-manager -o jsonpath='{.items[0].metadata.name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}) && \
	if ! kubectl get pods -n ${NAMESPACE} $$POD_NAME -o jsonpath='{.spec.volumes[*].name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "aws-iam-token"; then \
		echo "❌ aws-iam-token volume not found in acm-manager pod"; \
		echo "Pod identity webhook might not be mounting the token correctly"; \
		kubectl get pods -n ${NAMESPACE} $$POD_NAME -o yaml --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -A 20 "volumes:"; \
		exit 1; \
	else \
		echo "✅ aws-iam-token volume properly created"; \
	fi

	@echo "🔍 Checking for IAM token volume mount..."
	@POD_NAME=$$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=acm-manager -o jsonpath='{.items[0].metadata.name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}) && \
	if ! kubectl get pods -n ${NAMESPACE} $$POD_NAME -o jsonpath='{.spec.containers[0].volumeMounts[*].name}' --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "aws-iam-token"; then \
		echo "❌ aws-iam-token volume not mounted in acm-manager container"; \
		echo "Pod identity webhook might not be mounting the token correctly"; \
		kubectl get pods -n ${NAMESPACE} $$POD_NAME -o yaml --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -A 20 "volumeMounts:"; \
		exit 1; \
	else \
		MOUNT_PATH=$$(kubectl get pods -n ${NAMESPACE} $$POD_NAME -o jsonpath='{.spec.containers[0].volumeMounts[?(@.name=="aws-iam-token")].mountPath}' --kubeconfig=${TEST_KUBECONFIG_LOCATION}); \
		echo "✅ aws-iam-token volume properly mounted at path: $$MOUNT_PATH"; \
	fi

	@echo "✅ AWS configuration validation completed successfully"

.PHONY: uninstall-acm-manager-local
uninstall-acm-manager-local:
	$(HELM) uninstall acm-manager -n ${NAMESPACE}

.PHONY: upgrade-acm-manager-local
upgrade-acm-manager-local: uninstall-acm-manager-local install-acm-manager-local

.PHONY: cluster
cluster: generate setup-aws kind-cluster deploy-cert-manager setup-eks-webhook deploy-external-dns validate-external-dns-oidc install-acm-manager-local ## Sets up a kind cluster using the latest commit on the current branch
	@echo "🔵 Running final validation of all components..."
	@$(MAKE) validate-all
	@echo "✅ Cluster setup completed successfully"

##@ Test phase
.PHONY: e2etest
e2etest: ## Run end to end tests
	$(KIND) get kubeconfig --name ${K8S_CLUSTER_NAME} > ${TEST_KUBECONFIG_LOCATION}
	$(GO) test -v ./e2e/... -coverprofile cover.out

.PHONY: validate-all
validate-all: ## Validate all Kind cluster components are working properly
	@echo "🔍 Starting comprehensive Kind cluster validation..."
	@echo "🔍 Validating Kind cluster exists..."
	@if ! $(KIND) get clusters | grep -q "${K8S_CLUSTER_NAME}"; then \
		echo "❌ Kind cluster ${K8S_CLUSTER_NAME} not found"; \
		exit 1; \
	fi
	@echo "✅ Kind cluster ${K8S_CLUSTER_NAME} exists"
	@echo "🔍 Validating kubeconfig accessibility..."
	@if ! kubectl cluster-info --kubeconfig=${TEST_KUBECONFIG_LOCATION} >/dev/null 2>&1; then \
		echo "❌ Cannot access Kubernetes cluster"; \
		exit 1; \
	fi
	@echo "✅ Kubernetes cluster is accessible"
	@echo "🔍 Validating all pods are running..."
	@echo "Waiting for pods to be ready..."
	@kubectl wait --for=condition=ready --timeout=120s pods --all --all-namespaces --kubeconfig=${TEST_KUBECONFIG_LOCATION} 2>/dev/null || true
	@non_running_pods=$$(kubectl get pods -A --kubeconfig=${TEST_KUBECONFIG_LOCATION} --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | grep -v "NAMESPACE" || true); \
	if [ -z "$$non_running_pods" ]; then \
		echo "✅ All pods are running successfully"; \
	else \
		echo "⚠️ Some pods are not yet ready:"; \
		echo "$$non_running_pods"; \
		if echo "$$non_running_pods" | grep -q "ContainerCreating"; then \
			echo "⚠️ Some pods still creating - continuing anyway"; \
		elif echo "$$non_running_pods" | grep -q "Error\|CrashLoopBackOff"; then \
			echo "❌ Pod errors detected - cluster may not function correctly"; \
			exit 1; \
		fi; \
	fi
	@echo "🔍 Validating local registry accessibility..."
	@if ! curl -f http://127.0.0.1:${REGISTRY_PORT}/v2/ >/dev/null 2>&1; then \
		echo "❌ Local registry is not accessible"; \
		exit 1; \
	fi
	@echo "✅ Local registry is accessible"
	@echo "🔍 Validating cert-manager CRDs..."
	@if ! kubectl get crd --kubeconfig=${TEST_KUBECONFIG_LOCATION} | grep -q "cert-manager.io"; then \
		echo "❌ cert-manager CRDs not found"; \
		exit 1; \
	fi
	@echo "✅ cert-manager CRDs are installed"
	@echo "🔍 Validating cert-manager pods..."
	@if ! kubectl get pods -n cert-manager --kubeconfig=${TEST_KUBECONFIG_LOCATION} --field-selector=status.phase=Running | grep -q "cert-manager"; then \
		echo "❌ cert-manager pods are not running"; \
		kubectl get pods -n cert-manager --kubeconfig=${TEST_KUBECONFIG_LOCATION}; \
		exit 1; \
	fi
	@echo "✅ cert-manager pods are running"
	@echo "🔍 Validating EKS webhook deployment..."
	@if ! kubectl get deployment pod-identity-webhook --kubeconfig=${TEST_KUBECONFIG_LOCATION} -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q "1"; then \
		echo "❌ EKS pod-identity-webhook is not ready"; \
		kubectl get deployment pod-identity-webhook --kubeconfig=${TEST_KUBECONFIG_LOCATION}; \
		exit 1; \
	fi
	@echo "✅ EKS pod-identity-webhook is ready"
	@echo "🔍 Validating EKS webhook configuration..."
	@if ! kubectl get mutatingwebhookconfiguration pod-identity-webhook --kubeconfig=${TEST_KUBECONFIG_LOCATION} >/dev/null 2>&1; then \
		echo "❌ EKS webhook configuration not found"; \
		exit 1; \
	fi
	@echo "✅ EKS webhook configuration exists"
	@echo "🔍 Validating registry network configuration..."
	@if ! kubectl get configmap local-registry-hosting -n kube-public --kubeconfig=${TEST_KUBECONFIG_LOCATION} >/dev/null 2>&1; then \
		echo "❌ Registry network configuration not found"; \
		exit 1; \
	fi
	@echo "✅ Registry network configuration exists"
	@echo "🔍 Validating S3 OIDC configuration..."
	@if [[ -n "$$OIDC_S3_BUCKET_NAME" ]]; then \
		if ! aws s3 ls s3://$$OIDC_S3_BUCKET_NAME/cluster/acm-cluster/openid/v1/jwks >/dev/null 2>&1 || \
		   ! aws s3 ls s3://$$OIDC_S3_BUCKET_NAME/cluster/acm-cluster/.well-known/openid-configuration >/dev/null 2>&1; then \
			echo "❌ S3 OIDC configuration not found or inaccessible"; \
			exit 1; \
		fi; \
		echo "✅ S3 OIDC configuration is accessible"; \
	else \
		echo "⚠️ OIDC_S3_BUCKET_NAME not set, skipping S3 validation"; \
	fi
	@echo "🎉 All Kind cluster components validated successfully!"
	@echo "📊 Cluster Summary:"
	@kubectl get nodes --kubeconfig=${TEST_KUBECONFIG_LOCATION}
	@echo ""
	@kubectl get pods -A --kubeconfig=${TEST_KUBECONFIG_LOCATION}

##@ Cleanup all resources
.PHONY: cleanup
cleanup: clean-generated-code cleanup-aws cleanup-kind-cluster  ## Alias for complete Kind cleanup

.PHONY: clean-generated-code
clean-generated-code: ## Clean up all generated files
	@echo ">> cleaning generated files..."
	rm -rf pkg/client/applyconfiguration pkg/client/versioned
	rm -rf vdesjardins
	@# Clean up deepcopy files
	find pkg/apis -type f -name "zz_generated.deepcopy.go" -delete || true
	@# Clean up any leftover temporary files from sed
	find . -type f -name "*.go-e" -delete || true
	@echo "✅ Cleaned up generated files"


.PHONY: cleanup-aws
cleanup-aws: ## Cleanup AWS resources for OIDC
	if [[ -z "$$OIDC_S3_BUCKET_NAME" ]]; then \
		echo "OIDC_S3_BUCKET_NAME variable must be set"; \
		exit 1; \
	fi; \
	AWS_ACCOUNT=$(call get_aws_account); \
	if [[ -z "$$AWS_ACCOUNT" ]]; then \
		echo "AWS account could not be retrieved"; \
		exit 1; \
	fi
	./e2e/aws_config/cleanup.sh $$OIDC_S3_BUCKET_NAME

.PHONY: cleanup-kind-cluster
cleanup-kind-cluster: ## Complete cleanup of Kind cluster, registry, and temporary files
	@echo "🧹 Starting complete Kind cleanup..."
	@echo "🗑️ Deleting Kind cluster..."
	@$(KIND) delete cluster --name ${K8S_CLUSTER_NAME} 2>/dev/null || echo "ℹ️ Kind cluster ${K8S_CLUSTER_NAME} not found or already deleted"
	@echo "🗑️ Stopping and removing registry container..."
	@$(DOCKER) stop ${REGISTRY_NAME} 2>/dev/null || echo "ℹ️ Registry container not running"
	@$(DOCKER) rm ${REGISTRY_NAME} 2>/dev/null || echo "ℹ️ Registry container not found"
	@echo "🗑️ Cleaning up temporary files..."
	@rm -f /tmp/acm_manager_kubeconfig openid-configuration jwks /tmp/config.yaml 2>/dev/null || true
	@echo "🔍 Validating cleanup..."
	@if $(DOCKER) ps -a | grep -E "(${K8S_CLUSTER_NAME}|${REGISTRY_NAME})" >/dev/null 2>&1; then \
		echo "⚠️ Some containers may still exist:"; \
		$(DOCKER) ps -a | grep -E "(${K8S_CLUSTER_NAME}|${REGISTRY_NAME})"; \
	else \
		echo "✅ No Kind/registry containers found"; \
	fi
	@if $(KIND) get clusters 2>/dev/null | grep -q "${K8S_CLUSTER_NAME}"; then \
		echo "⚠️ Kind cluster ${K8S_CLUSTER_NAME} still exists"; \
	else \
		echo "✅ No Kind clusters found"; \
	fi
	@echo "✅ Complete Kind cleanup finished"
