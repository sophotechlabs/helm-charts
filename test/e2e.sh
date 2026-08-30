#!/usr/bin/env bash
# Orchestration only. The per-release assertions live in the charts as
# `helm test` hooks, so anyone installing these charts gets the same checks
# rather than them existing only in CI.
#
# What is left here is the part a single release cannot assert: behaviour
# across an upgrade. Whether a password the user chose survives a reconcile,
# and whether removing a user from the file takes their access away.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTX="${KUBECONFIG_CONTEXT:-}"
NS="${E2E_NAMESPACE:-keycloak-e2e}"
RELEASE=kc
CONFIG_RELEASE=kcc
REALM=e2e
ADMIN_PASSWORD="e2e-admin-$RANDOM$RANDOM"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$1" >&2; exit 1; }
ok()   { printf '  ok    %s\n' "$1"; }

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

kcadm() {
  k -n "$NS" exec "sts/$RELEASE-keycloak" -c keycloak -- \
    /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config
}

apply_realm() {
  # The apply job's name carries a hash of the realm, so a changed realm makes
  # a new job. Waiting on the label picks up whichever one this upgrade made.
  h upgrade --install "$CONFIG_RELEASE" "$REPO_ROOT/charts/keycloak-config" \
    --namespace "$NS" "$@" --wait --timeout 5m
  k -n "$NS" wait --for=condition=complete --timeout=5m \
    job -l "app.kubernetes.io/instance=$CONFIG_RELEASE,app.kubernetes.io/component=apply"
}

step "reset"
# From a known state every time. Keycloak's bootstrap admin only applies while
# the master realm does not exist, so a second run against a surviving
# namespace writes a fresh random password into the secret that the already
# created account does not have — and every later step fails for a reason that
# has nothing to do with the charts.
if k get ns "$NS" >/dev/null 2>&1; then
  k delete ns "$NS" --wait --timeout=5m
fi
k create ns "$NS"
k -n "$NS" create secret generic keycloak-admin \
  --from-literal=password="$ADMIN_PASSWORD" \
  --dry-run=client -o yaml | k apply -f -
k -n "$NS" create secret generic realm-secrets \
  --from-literal=ALICE_PASSWORD="alice-initial-$RANDOM" \
  --from-literal=GRAFANA_CLIENT_SECRET="grafana-$RANDOM$RANDOM" \
  --dry-run=client -o yaml | k apply -f -

step "install keycloak"
h upgrade --install "$RELEASE" "$REPO_ROOT/charts/keycloak" \
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

step "helm test keycloak"
h test "$RELEASE" --namespace "$NS" --timeout 5m
ok "health endpoints and master realm discovery answer"

step "authenticate"
# Ahead of the apply on purpose: config-cli's availability check retries for
# five minutes and then reports a transport error, so a credential problem
# surfaces here in seconds with the actual reason instead.
k -n "$NS" exec "sts/$RELEASE-keycloak" -c keycloak -- \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --config /tmp/kcadm.config \
  --server http://localhost:8080 --realm master \
  --user admin --password "$ADMIN_PASSWORD"
ok "admin cli authenticated"

step "apply a realm"
# Written by a function rather than edited later with sed or grep: removing a
# user has to remove the whole block, and a line-wise edit that leaves an
# orphaned firstName behind would attach it to whoever came before.
write_realm() {
  cat > "$1" <<EOF
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
    emailVerified: true
    firstName: Alice
    lastName: Example
    requiredActions: []
    credentials:
      - type: password
        value: \$(env:ALICE_PASSWORD)
        userLabel: initial
    groups:
      - /admins
EOF
  if [ "${2:-with-bob}" = "with-bob" ]; then
    cat >> "$1" <<EOF
  - username: bob
    enabled: true
    email: bob@e2e.test
    emailVerified: true
    firstName: Bob
    lastName: Example
    requiredActions: []
EOF
  fi
}

write_realm "$WORK/realm.yaml"
write_realm "$WORK/realm-no-bob.yaml" without-bob

apply_realm \
  --set keycloak.url="http://$RELEASE-keycloak.$NS.svc.cluster.local:8080" \
  --set auth.existingSecret=keycloak-admin \
  --set auth.username=admin \
  --set substitution.existingSecret=realm-secrets \
  --set reconcile.enabled=false \
  --set-file realm.spec="$WORK/realm.yaml"
ok "apply job completed"

step "helm test keycloak-config"
# This is the assertion that the realm, its groups, its clients and every
# user's group membership match the file. It lives in the chart.
h test "$CONFIG_RELEASE" --namespace "$NS" --timeout 5m
ok "the realm matches the file"

step "a password the user chose survives a reconcile"
# Measured on the credential itself rather than by trying to log in: a login
# can fail for reasons that have nothing to do with the password (a pending
# required action reads as "Account is not fully set up"), and a test that
# cannot tell those apart would report the wrong cause.
#
# Keycloak updates the password credential in place rather than replacing it —
# measured on 26.7.2: the credential id is stable across a set-password while
# createdDate moves. So createdDate is the signal, and the id is not.
#
# The middle step exists to prove the measurement is sensitive before the last
# one relies on it. It is what caught the id being the wrong field.
alice_credential_date() {
  ID=$(kcadm get users -r "$REALM" -q username=alice -q exact=true --fields id --format csv --noquotes | tr -d '\r')
  [ -n "$ID" ] || fail "could not resolve alice"
  kcadm get "users/$ID/credentials" -r "$REALM" --fields createdDate --format csv --noquotes | tr -d '\r' | head -1
}

BEFORE=$(alice_credential_date)
[ -n "$BEFORE" ] || fail "alice has no credential to start with"
ok "credential createdDate before: $BEFORE"

CHOSEN="alice-chose-this-$RANDOM$RANDOM"
kcadm set-password -r "$REALM" --username alice --new-password "$CHOSEN"
CHANGED=$(alice_credential_date)
[ "$CHANGED" != "$BEFORE" ] || fail "changing the password out of band did not move the credential createdDate, so this test cannot detect a rewrite"
ok "password changed out of band, createdDate now $CHANGED"

k -n "$NS" delete job -l "app.kubernetes.io/instance=$CONFIG_RELEASE,app.kubernetes.io/component=apply" --ignore-not-found
apply_realm --reuse-values --set reconcile.cache=false --set-file realm.spec="$WORK/realm.yaml"

AFTER=$(alice_credential_date)
[ "$AFTER" = "$CHANGED" ] || fail "the reconcile rewrote alice's password (createdDate $CHANGED -> $AFTER), so userLabel: initial did not make the credential create-only"
ok "password untouched by the reconcile, createdDate still $AFTER"

step "removing a user from the file takes their access away"
k -n "$NS" delete job -l "app.kubernetes.io/instance=$CONFIG_RELEASE,app.kubernetes.io/component=apply" --ignore-not-found
apply_realm --reuse-values --set prune.enabled=true --set-file realm.spec="$WORK/realm-no-bob.yaml"

BOB=$(kcadm get users -r "$REALM" -q username=bob -q exact=true --fields enabled --format csv --noquotes | tr -d '\r')
[ "$BOB" = "false" ] || fail "bob is still enabled after being removed from the realm file (got '$BOB')"
ok "bob was disabled"

ALICE=$(kcadm get users -r "$REALM" -q username=alice -q exact=true --fields enabled --format csv --noquotes | tr -d '\r')
[ "$ALICE" = "true" ] || fail "alice was disabled and should not have been"
ok "alice is untouched"

printf '\n\033[32mall end-to-end assertions passed\033[0m\n'
