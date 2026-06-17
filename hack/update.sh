#!/usr/bin/env bash
# Vendor the upstream NVIDIA Dynamo platform Helm chart into
# charts/cozy-nvidia-dynamo/charts/dynamo-platform/.
#
# Run this when bumping the upstream version. The output is committed to
# git so CI does not need network access for chart deps at release time.
#
# Pinned upstream tag is the single source of truth; bump UPSTREAM_TAG to
# upgrade.

set -euo pipefail

UPSTREAM_REPO="https://github.com/ai-dynamo/dynamo.git"
UPSTREAM_TAG="${UPSTREAM_TAG:-v1.2.1}"
CHART_PATH="deploy/helm/charts/platform"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER_DIR="${REPO_ROOT}/charts/cozy-nvidia-dynamo"
VENDOR_DIR="${WRAPPER_DIR}/charts/dynamo-platform"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "==> Cloning ${UPSTREAM_REPO} @ ${UPSTREAM_TAG}"
git clone --depth=1 --branch "${UPSTREAM_TAG}" "${UPSTREAM_REPO}" "${WORKDIR}/dynamo"

echo "==> Staging ${CHART_PATH}"
rm -rf "${VENDOR_DIR}"
mkdir -p "${VENDOR_DIR}"
cp -R "${WORKDIR}/dynamo/${CHART_PATH}/." "${VENDOR_DIR}/"

echo "==> Removing Bitnami etcd dependency from Chart.yaml"
# Bitnami images are forbidden in this org. The upstream chart gates etcd
# behind `global.etcd.install`; we drop the dependency outright so the
# Bitnami chart never enters helm-dep-build resolution. Operators that
# need etcd point the platform at an existing cozystack-managed Etcd via
# values.yaml overrides.
python3 - "${VENDOR_DIR}/Chart.yaml" <<'PY'
import sys, re
path = sys.argv[1]
with open(path) as f:
    raw = f.read()
# Strip the etcd dependency block — match the YAML list item starting with
# "  - name: etcd" up to (but not including) the next list item or EOF.
pattern = re.compile(
    r"^  - name: etcd\n(?:    [^\n]*\n)+",
    flags=re.MULTILINE,
)
new = pattern.sub("", raw, count=1)
if new == raw:
    print("WARNING: etcd dependency block not found in upstream Chart.yaml — may already be removed.", file=sys.stderr)
with open(path, "w") as f:
    f.write(new)
PY

echo "==> Adding required helm repositories"
helm repo add nats https://nats-io.github.io/k8s/helm/charts/ >/dev/null 2>&1 || true
helm repo update nats >/dev/null

echo "==> Running helm dependency build"
(cd "${VENDOR_DIR}" && helm dependency build)

echo "==> Untarring fetched dep .tgz archives so the result is git-friendly"
# helm dep build writes .tgz files under charts/. Untar them so the diff
# is reviewable and OCI artifacts do not embed redundant nested tarballs.
if compgen -G "${VENDOR_DIR}/charts/*.tgz" > /dev/null; then
    (cd "${VENDOR_DIR}/charts" && for tgz in *.tgz; do
        tar xzf "${tgz}"
        rm -f "${tgz}"
    done)
fi
rm -f "${VENDOR_DIR}/Chart.lock"

echo
echo "Vendored chart placed at: ${VENDOR_DIR#${REPO_ROOT}/}"
echo "Upstream tag pinned in this script: UPSTREAM_TAG=${UPSTREAM_TAG}"
echo "Bump that var and re-run to upgrade."
