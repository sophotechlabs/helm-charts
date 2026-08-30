# helm-charts

Helm charts published by [Sophotech](https://sopho.tech).

| Chart | What it does |
|---|---|
| [`keycloak`](charts/keycloak) | Runs Keycloak. Creates its database, certificate, route and backups too — or none of them, if you already have your own. |
| [`keycloak-config`](charts/keycloak-config) | Keeps a Keycloak realm — clients, scopes, roles, groups and users — matching a YAML file in git. |

## Install

```sh
helm install keycloak oci://ghcr.io/sophotechlabs/charts/keycloak
helm install keycloak-config oci://ghcr.io/sophotechlabs/charts/keycloak-config \
  --set-file realm.spec=./realm.yaml
```

Every release is signed. Verify before installing:

```sh
cosign verify oci://ghcr.io/sophotechlabs/charts/keycloak \
  --certificate-identity-regexp '^https://github\.com/sophotechlabs/helm-charts/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Design

Both charts follow the same two rules.

**Batteries included, every battery removable.** The `keycloak` chart will create a CloudNativePG cluster, a cert-manager `Certificate`, a Traefik `IngressRoute` and a backup `CronJob` for you. Every one of them is a mode value you can switch to something else or turn off, and nothing is auto-detected — a chart that renders differently depending on which CRDs happen to be installed renders differently under `helm template`, under a Flux dry-run and in your cluster, which is how surprises happen. With everything off, these charts install on a cluster with no CRDs at all.

**Say what it actually does.** `keycloak-config` applies a realm definition and enforces role and group membership. It does not delete users, because the tool underneath cannot — see [its README](charts/keycloak-config#what-reconciliation-means-here) for exactly what happens when you remove a user from the file.

## Support

None. These are published because they are built and tested in the open, not because anyone is on call for them. Issues are not monitored, versions carry no compatibility promise to anyone, and you should read a chart before you run it.

Bug reports are still welcome; expectations of a reply are not.

## License

Apache-2.0. Copyright 2026 Sophotech s.r.o.

Keycloak™ is a trademark of the Linux Foundation. These charts are not affiliated with, endorsed by, or supported by the Keycloak project.
