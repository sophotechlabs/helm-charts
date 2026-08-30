#!/usr/bin/env bash
# The other claim: with every optional piece switched off, the charts install
# on a cluster that has none of the CRDs they can otherwise use.
#
# This has to run on a cluster where those CRDs are genuinely absent. Checking
# it on the same cluster as hack/e2e.sh would prove nothing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTX="${KUBECONFIG_CONTEXT:-}"
NS="${BARE_NAMESPACE:-keycloak-bare}"
RELEASE=bare

k() {
  if [ -n "$CTX" ]; then
    kubectl --context "$CTX" "$@"
  else
    kubectl "$@"
  fi
}

h() {
  if [ -n "$CTX" ]; then
    helm --kube-context "$CTX" "$@"
  else
    helm "$@"
  fi
}

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$1" >&2; exit 1; }
ok()   { printf '  ok    %s\n' "$1"; }

step "the cluster really is bare"
for crd in \
  clusters.postgresql.cnpg.io \
  certificates.cert-manager.io \
  ingressroutes.traefik.io \
  httproutes.gateway.networking.k8s.io \
  servicemonitors.monitoring.coreos.com
do
  if k get crd "$crd" >/dev/null 2>&1; then
    fail "$crd is installed, so this run would not prove anything"
  fi
done
ok "none of the optional CRDs are present"

k get ns "$NS" >/dev/null 2>&1 || k create ns "$NS"

step "a plain postgres for the external-database path"
k -n "$NS" apply -f - <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: postgres
type: Opaque
stringData:
  username: keycloak
  password: keycloak
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels: { app: postgres }
  template:
    metadata:
      labels: { app: postgres }
    spec:
      containers:
        - name: postgres
          image: postgres:18.4-alpine
          env:
            - name: POSTGRES_USER
              value: keycloak
            - name: POSTGRES_PASSWORD
              value: keycloak
            - name: POSTGRES_DB
              value: keycloak
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          ports:
            - containerPort: 5432
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "keycloak"]
            periodSeconds: 5
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: data
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  selector: { app: postgres }
  ports:
    - port: 5432
      targetPort: 5432
YAML
k -n "$NS" rollout status deployment/postgres --timeout=5m
ok "postgres ready"

step "install with everything optional turned off"
h upgrade --install "$RELEASE" "$REPO_ROOT/charts/keycloak" \
  --namespace "$NS" \
  --set keycloak.hostname=http://auth.bare.test \
  --set keycloak.hostnameStrict=false \
  --set admin.existingSecret=keycloak-admin \
  --set admin.username=admin \
  --set database.mode=external \
  --set database.host=postgres \
  --set database.existingSecret=postgres \
  --set tls.mode=none \
  --set route.mode=none \
  --set backup.mode=none \
  --set metrics.enabled=false \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=512Mi \
  --wait --timeout 15m &
INSTALL_PID=$!

k -n "$NS" create secret generic keycloak-admin \
  --from-literal=password="bare-admin" \
  --dry-run=client -o yaml | k apply -f -

wait "$INSTALL_PID" || fail "install failed on a cluster with no CRDs"
ok "installed with no CRDs present"

step "helm test"
h test "$RELEASE" --namespace "$NS" --timeout 5m
ok "keycloak answers on a bare cluster"

step "nothing custom was created"
if k -n "$NS" get all -o name | grep -qiE 'cluster|certificate|ingressroute'; then
  fail "the release created a custom resource it should not have"
fi
ok "only core objects exist"

printf '\n\033[32mbare-cluster install verified\033[0m\n'
