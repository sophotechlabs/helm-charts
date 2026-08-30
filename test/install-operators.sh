#!/usr/bin/env bash
# Installs the operators the end-to-end run needs to actually work. The render
# checks do not need this: they validate against the CRD schema catalog rather
# than against a cluster.
set -euo pipefail

CNPG_VERSION="${CNPG_VERSION:-1.28.1}"
CTX="${KUBECONFIG_CONTEXT:-}"

k() {
  if [ -n "$CTX" ]; then
    kubectl --context "$CTX" "$@"
  else
    kubectl "$@"
  fi
}

if k -n cnpg-system get deployment cnpg-controller-manager >/dev/null 2>&1; then
  echo "==> cloudnative-pg already installed"
else
  echo "==> cloudnative-pg ${CNPG_VERSION}"
  k apply --server-side --force-conflicts \
    -f "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_VERSION%.*}/releases/cnpg-${CNPG_VERSION}.yaml"
fi

k -n cnpg-system rollout status deployment/cnpg-controller-manager --timeout=5m
echo "==> operators ready"
