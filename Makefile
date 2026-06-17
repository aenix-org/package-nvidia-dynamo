.PHONY: update lint template package push push-bundle clean help

CHART_DIR    := charts/cozy-nvidia-dynamo
PLATFORM_DIR := packages/core/platform
DIST_DIR     := _dist

REGISTRY    := ghcr.io/aenix-org
CHARTS_REPO := $(REGISTRY)/charts
BUNDLE_REPO := $(REGISTRY)/package-nvidia-dynamo-platform-packages

CHART_VERSION := $(shell awk '/^version:/ {gsub(/"/, "", $$2); print $$2}' $(CHART_DIR)/Chart.yaml)

help:
	@echo "Targets:"
	@echo "  update       Vendor upstream NVIDIA Dynamo platform chart into $(CHART_DIR)/charts/"
	@echo "  lint         Helm-lint wrapper and platform charts"
	@echo "  template     Render both charts to stdout (sanity check)"
	@echo "  package      helm package the wrapper chart into $(DIST_DIR)/"
	@echo "  push         Push packaged charts to $(CHARTS_REPO)"
	@echo "  push-bundle  flux push the platform bundle to $(BUNDLE_REPO):$(CHART_VERSION)"
	@echo "  clean        Remove $(DIST_DIR)/"
	@echo
	@echo "Override UPSTREAM_TAG to vendor a different upstream version:"
	@echo "  make update UPSTREAM_TAG=v1.2.1"
	@echo
	@echo "OCI push targets require GHCR auth — log in with:"
	@echo "  gh auth token | helm registry login ghcr.io --username YOUR_USER --password-stdin"
	@echo "  gh auth token | docker login ghcr.io --username YOUR_USER --password-stdin"

update:
	UPSTREAM_TAG=$${UPSTREAM_TAG:-v1.2.1} hack/update.sh

lint:
	helm lint $(CHART_DIR)
	helm lint $(PLATFORM_DIR)

template:
	@echo "=== $(CHART_DIR) ==="
	helm template ci $(CHART_DIR)
	@echo "=== $(PLATFORM_DIR) ==="
	helm template ci $(PLATFORM_DIR)

package: lint
	mkdir -p $(DIST_DIR)
	helm package $(CHART_DIR) --destination $(DIST_DIR)

push: package
	@for tgz in $(DIST_DIR)/*.tgz; do \
		echo "Pushing $$tgz to oci://$(CHARTS_REPO)" ; \
		helm push "$$tgz" oci://$(CHARTS_REPO) ; \
	done

push-bundle:
	flux push artifact \
		oci://$(BUNDLE_REPO):$(CHART_VERSION) \
		--path=packages \
		--source="https://github.com/aenix-org/package-nvidia-dynamo" \
		--revision="$(CHART_VERSION)@sha1:$(shell git rev-parse HEAD 2>/dev/null || echo local)"

clean:
	rm -rf $(DIST_DIR)
