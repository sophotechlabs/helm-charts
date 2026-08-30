#!/usr/bin/env bash
# The claim this repo exists to make, checked against a running Keycloak:
# a realm file in git becomes users, groups and role mappings, a password the
# user changes is not reverted by the next reconcile, and a user removed from
# the file loses their access.
#
# Nothing here is a stub. Every assertion is read back from the Keycloak admin
# API on the cluster.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="${E2E_NAMESPACE:-keycloak-e2e}"
RELEASE=kc
CONFIG_RELEASE=kcc
REALM=e2e
ADMIN_PASSWORD="${E2E_ADMIN_PASSWORD:-e2e-admin-$RANDOM}"
ALICE_PASSWORD="alice-initial-$RANDOM"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$1" >&2; exit 1; }
ok()   { printf '  ok    %s\n' "$1"; }

kc() {
  # kcadm inside the running pod: no port-forward, no extra tooling, and it
  # exercises the same server a client would.
  kubectl -n "$NS" exec "sts/$RELEASE-keycloak" -c keycloak -- \
    /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config
}

step "cluster"
if ! kubectl cluster-info >/dev/null 2>&1; then
  fail "no reachable cluster; run just kind-up first"
fi
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

step "operators"
"$REPO_ROOT/hack/install-operators.sh"

step "secrets"
kubectl -n "$NS" create secret generic keycloak-admin \
  --from-literal=password="$ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic realm-secrets \
  --from-literal=ALICE_PASSWORD="$ALICE_PASSWORD" \
  --from-literal=GRAFANA_CLIENT_SECRET="grafana-$RANDOM" \
  --dry-run=client -o yaml | kubectl apply -f -

step "install keycloak"
helm upgrade --install "$RELEASE" "$REPO_ROOT/charts/keycloak" \
  --namespace "$NS" \
  --set keycloak.hostname=http://auth.e2e.test \
  --set keycloak.hostnameStrict=false \
  --set admin.existingSecret=keycloak-admin \
  --set admin.username=admin \
  --set database.mode=cnpg \
  --set database.cnpg.storage.size=1Gi \
  --set tls.mode=none \
  --set route.mode=none \
  --set backup.mode=none \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=512Mi \
  --wait --timeout 15m
ok "keycloak ready"

step "helm test"
helm test "$RELEASE" --namespace "$NS" --timeout 5m
ok "health and discovery endpoints answer"

step "authenticate"
kubectl -n "$NS" exec "sts/$RELEASE-keycloak" -c keycloak -- \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --config /tmp/kcadm.config \
  --server "http://localhost:8080" --realm master \
  --user admin --password "$ADMIN_PASSWORD"
ok "admin cli authenticated"

step "apply a realm"
cat > "$WORK/realm.yaml" <<EOF
realm: $REALM
enabled: true
roles:
  client:
    grafana:
      - name: admin
groups:
  - name: admins
    clientRoles:
      grafana:
        - admin
clients:
  - clientId: grafana
    enabled: true
    protocol: openid-connect
    publicClient: false
    secret: \$(env:GRAFANA_CLIENT_SECRET)
    redirectUris:
      - http://grafana.e2e.test/login/generic_oauth
users:
  - username: alice
    enabled: true
    email: alice@e2e.test
    firstName: Alice
    lastName: Example
    credentials:
      - type: password
        value: \$(env:ALICE_PASSWORD)
        userLabel: initial
    groups:
      - /admins
  - username: bob
    enabled: true
    email: bob@e2e.test
EOF

helm upgrade --install "$CONFIG_RELEASE" "$REPO_ROOT/charts/keycloak-config" \
  --namespace "$NS" \
  --set keycloak.url="http://$RELEASE-keycloak.$NS.svc.cluster.local:8080" \
  --set auth.existingSecret=keycloak-admin \
  --set auth.username=admin \
  --set substitution.existingSecret=realm-secrets \
  --set reconcile.enabled=false \
  --set-file realm.spec="$WORK/realm.yaml" \
  --wait --timeout 5m

kubectl -n "$NS" wait --for=condition=complete --timeout=5m \
  job -l "app.kubernetes.io/instance=$CONFIG_RELEASE,app.kubernetes.io/component=apply"
ok "apply job completed"

step "the realm is what the file said"
kc get "realms/$REALM" --fields realm --format csv --noquotes | grep -qx "$REALM" \
  || fail "realm $REALM was not created"
ok "realm exists"

for user in alice bob; do
  kc get users -r "$REALM" -q "username=$user" -q exact=true --fields username --format csv --noquotes \
    | grep -qx "$user" || fail "user $user was not created"
  ok "user $user exists"
done

ALICE_ID=$(kc get users -r "$REALM" -q username=alice -q exact=true --fields id --format csv --noquotes | tr -d '\r')
[ -n "$ALICE_ID" ] || fail "could not resolve alice's id"

kc get "users/$ALICE_ID/groups" -r "$REALM" --fields name --format csv --noquotes \
  | grep -qx admins || fail "alice is not in the admins group"
ok "alice is in admins"

kc get clients -r "$REALM" -q clientId=grafana --fields clientId --format csv --noquotes \
  | grep -qx grafana || fail "the grafana client was not created"
ok "grafana client exists"

step "a password the user chose is not reverted"
# userLabel: initial makes the credential create-only. Change it out of band,
# re-apply the same realm, and the new password must survive.
CHOSEN="alice-chose-this-$RANDOM"
kc set-password -r "$REALM" --username alice --new-password "$CHOSEN"
ok "password changed out of band"

kubectl -n "$NS" delete job -l "app.kubernetes.io/instance=$CONFIG_RELEASE,app.kubernetes.io/component=apply" --ignore-not-found
helm upgrade "$CONFIG_RELEASE" "$REPO_ROOT/charts/keycloak-config" \
  --namespace "$NS" --reuse-values \
  --set reconcile.cache=false \
  --set-file realm.spec="$WORK/realm.yaml" \
  --wait --timeout 5m
kubectl -n "$NS" wait --for=condition=complete --timeout=5m \
  job -l "app.kubernetes.io/instance=$CONFIG_RELEASE,app.kubernetes.io/component=apply"

# A direct grant proves the password rather than trusting the absence of a
# write: this fails if config-cli re-hashed the credential.
kubectl -n "$NS" exec "sts/$RELEASE-keycloak" -c keycloak -- \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --config /tmp/alice.config \
  --server http://localhost:8080 --realm "$REALM" \
  --client admin-cli --user alice --password "$CHOSEN" \
  || fail "alice's chosen password was reverted by the reconcile"
ok "chosen password survived a reconcile"

step "removing a user from the file strips their access"
sed -e '/username: bob/,+1d' "$WORK/realm.yaml" > "$WORK/realm-no-bob.yaml"
kubectl -n "$NS" delete job -l "app.kubernetes.io/instance=$CONFIG_RELEASE,app.kubernetes.io/component=apply" --ignore-not-found
helm upgrade "$CONFIG_RELEASE" "$REPO_ROOT/charts/keycloak-config" \
  --namespace "$NS" --reuse-values \
  --set prune.enabled=true \
  --set-file realm.spec="$WORK/realm-no-bob.yaml" \
  --wait --timeout 5m
kubectl -n "$NS" wait --for=condition=complete --timeout=5m \
  job -l "app.kubernetes.io/instance=$CONFIG_RELEASE,app.kubernetes.io/component=apply"

BOB_ENABLED=$(kc get users -r "$REALM" -q username=bob -q exact=true --fields enabled --format csv --noquotes | tr -d '\r')
[ "$BOB_ENABLED" = "false" ] || fail "bob is still enabled after being removed from the realm file (got '$BOB_ENABLED')"
ok "bob was disabled by the prune step"

ALICE_STILL=$(kc get users -r "$REALM" -q username=alice -q exact=true --fields enabled --format csv --noquotes | tr -d '\r')
[ "$ALICE_STILL" = "true" ] || fail "alice was disabled and should not have been"
ok "alice is untouched"

printf '\n\033[32mall end-to-end assertions passed\033[0m\n'
