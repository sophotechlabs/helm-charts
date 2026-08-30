#!/usr/bin/env bash
# Installs the CRDs the non-bare CI scenarios need, into whatever cluster
# kubectl currently points at. Operators themselves are deliberately not
# installed: the scenarios assert that the chart produces valid custom
# resources, not that a third-party controller acts on them.
set -euo pipefail

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.19.1}"
TRAEFIK_VERSION="${TRAEFIK_VERSION:-v37.1.2}"
CNPG_VERSION="${CNPG_VERSION:-1.28.1}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.4.0}"
PROMETHEUS_OPERATOR_VERSION="${PROMETHEUS_OPERATOR_VERSION:-v0.87.0}"

apply() {
  echo "==> $1"
  kubectl apply --server-side --force-conflicts -f "$2"
}

apply "cert-manager ${CERT_MANAGER_VERSION} CRDs" \
  "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml"

apply "gateway-api ${GATEWAY_API_VERSION} CRDs" \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

apply "cloudnative-pg ${CNPG_VERSION} CRDs" \
  "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_VERSION%.*}/releases/cnpg-${CNPG_VERSION}.yaml"

for crd in servicemonitors podmonitors probes; do
  apply "prometheus-operator ${PROMETHEUS_OPERATOR_VERSION} ${crd}" \
    "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROMETHEUS_OPERATOR_VERSION}/example/prometheus-operator-crd/monitoring.coreos.com_${crd}.yaml"
done

echo "==> traefik ${TRAEFIK_VERSION} CRDs"
helm template traefik-crds traefik \
  --repo https://traefik.github.io/charts \
  --version "${TRAEFIK_VERSION}" \
  --set installCRDs=true \
  --include-crds \
  --show-only 'crds/*' 2>/dev/null | kubectl apply --server-side --force-conflicts -f - || {
  echo "traefik chart CRD extraction failed; falling back to the CRD bundle"
  kubectl apply --server-side --force-conflicts \
    -f "https://raw.githubusercontent.com/traefik/traefik/${TRAEFIK_VERSION}/integration/fixtures/k8s/01-traefik-crd.yml"
}

kubectl wait --for=condition=Established --timeout=120s crd --all
echo "==> CRDs ready"
