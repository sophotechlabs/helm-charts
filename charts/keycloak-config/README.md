# keycloak-config

Keeps a Keycloak realm — clients, scopes, roles, groups and users — matching a YAML file in git

![Version: 0.0.0](https://img.shields.io/badge/Version-0.0.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 6.5.1](https://img.shields.io/badge/AppVersion-6.5.1-informational?style=flat-square)

## Install

Supply the realm by path:

```sh
helm install keycloak-config oci://ghcr.io/sophotechlabs/charts/keycloak-config \
  --set keycloak.url=http://keycloak.keycloak.svc.cluster.local:8080 \
  --set auth.existingSecret=keycloak-admin \
  --set substitution.existingSecret=keycloak-realm-secrets \
  --set-file realm.spec=./realm.yaml
```

Under Flux, where there is no `--set-file`, point `valuesFrom` at a key:

```yaml
valuesFrom:
  - kind: ConfigMap
    name: keycloak-realm
    valuesKey: realm.yaml
    targetPath: realm.spec
```

## What reconciliation means here

This is the part to read before relying on it. The work is done by [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli), and its semantics are not what "reconcile" usually implies.

**Applied and enforced.** Realm settings, clients, client scopes, protocol mappers, realm and client roles, groups, and each user's role and group membership. Remove a role from a user in the file and the next run removes it in Keycloak.

**Created, not enforced.** User passwords. The chart *requires* every password credential to carry `userLabel: initial`, and refuses to install otherwise. That makes the credential apply only when the user is created.

The reason is worth stating plainly: config-cli compares the user it is about to write against the one the admin API returns, and the returned user never carries credentials — so a user with a password in the file always compares as changed, and Keycloak re-hashes the password on every run. On a fifteen-minute schedule that silently reverts whatever password the person chose for themselves. The `userLabel` is the documented, code-enforced way out, so this chart makes it mandatory rather than optional.

For the same reason `temporary: true` is rejected: it re-adds the `UPDATE_PASSWORD` required action on every run, prompting a user who already changed their password.

**Not done: deleting users.** config-cli cannot; it says so in its own logs. Removing a user from the file strips their roles and group memberships, so they lose access, but the account remains and can still log in to anything that does not check a role.

`prune.enabled` closes that gap by disabling those accounts through the admin API after each apply. It is off by default because it acts on users this chart never created. It skips Keycloak's own `service-account-*` users, honours `prune.exclude`, and refuses to act at all if it cannot enumerate every user in the realm — disabling accounts on a partial view is not something to do quietly.

## Drift, and the setting that decides whether there is any

`reconcile.cache` defaults to **false**, and that is deliberate.

config-cli stores a checksum of the realm file as an attribute on the realm and, when the cache is on, skips the entire import when the file is unchanged — clients, roles, groups and users alike. With the cache on, a schedule re-applies only after a git change, and anything edited in the admin console stays edited. That is the upstream default and it is what most people are unknowingly running.

With the cache off, every scheduled run is a full apply, which is what makes the schedule correct drift. The cost is a full realm write against a live server on every tick, and config-cli takes no lock of its own — which is why the CronJob sets `concurrencyPolicy: Forbid`.

## Version ceiling

config-cli's image tag carries the Keycloak version its admin client was built against (`6.5.1-26.5.5`). The realm parser rejects unknown fields outright rather than ignoring them, so a Keycloak newer than the tag can fail the whole import on a single new realm key. Check the [published tags](https://hub.docker.com/r/adorsys/keycloak-config-cli/tags) before upgrading the server.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity for the jobs. |
| apply.backoffLimit | int | `3` | Retries before the apply is given up on. |
| apply.enabled | bool | `true` | Run once per release, applying the realm as soon as the chart is installed or upgraded. The job's name carries a hash of the realm, so a changed realm creates a new job rather than trying to patch an immutable one. |
| apply.ttlSecondsAfterFinished | int | `3600` | Seconds a finished apply job is kept before Kubernetes removes it. |
| auth.clientId | string | `""` | Client ID, when mode is `client`. |
| auth.clientSecretKey | string | `"client-secret"` | Key in the secret holding the client secret, when mode is `client`. |
| auth.existingSecret | string | `""` | Secret holding the credential. Required — the admin CLI otherwise falls back to an interactive prompt, which in a Job hangs rather than fails. |
| auth.mode | string | `"password"` | `password` authenticates as a user; `client` uses a confidential client's service account, which is the better fit for an unattended job. |
| auth.passwordKey | string | `"password"` | Key in the secret holding the admin password, when mode is `password`. |
| auth.username | string | `"admin"` | Admin username, when mode is `password`. |
| commonAnnotations | object | `{}` | Annotations added to every object this chart creates. |
| commonLabels | object | `{}` | Labels added to every object this chart creates. |
| configCli.availabilityCheck | object | `{"enabled":true,"timeout":"300s"}` | Wait for Keycloak to answer before importing. config-cli's own default is not to wait, which fails a job that starts alongside Keycloak. |
| configCli.availabilityCheck.enabled | bool | `true` | Wait for Keycloak to become available. |
| configCli.availabilityCheck.timeout | string | `"300s"` | How long to wait. |
| configCli.extraEnv | list | `[]` | Extra `IMPORT_*` / `KEYCLOAK_*` environment for config-cli. |
| configCli.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| configCli.image.registry | string | `"docker.io"` | keycloak-config-cli image registry. |
| configCli.image.repository | string | `"adorsys/keycloak-config-cli"` | keycloak-config-cli image repository. |
| configCli.image.tag | string | `"6.5.1-26.5.5"` | Image tag. The suffix is the Keycloak version its admin client was built against; the realm parser rejects unknown fields outright, so a server newer than this tag can fail the whole import. |
| configCli.logLevel | string | `"info"` | Log level. Note that setting the realm-config logger to trace prints the fully substituted realm, passwords included. |
| configCli.managed | object | `{"authenticationFlow":"no-delete","client":"full","clientScope":"full","group":"full","identityProvider":"no-delete","identityProviderMapper":"no-delete","requiredAction":"no-delete","role":"full","scopeMapping":"full","subGroup":"full"}` | Per-entity deletion policy, `import.managed.*`. `full` deletes entities present in Keycloak and absent from the file; `no-delete` leaves them. Authentication flows and identity providers are called out because their deletions are not bounded by remote state. |
| containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":false}` | Container security context. `readOnlyRootFilesystem` is false because the config-cli JVM writes to its own root filesystem. |
| extraObjects | list | `[]` | Arbitrary extra manifests, rendered through `tpl`. |
| extraVolumeMounts | list | `[]` | Extra volume mounts on the config-cli container. |
| extraVolumes | list | `[]` | Extra volumes on the jobs. |
| fullnameOverride | string | `""` | Override the full release-qualified name used for every resource. |
| imagePullSecrets | list | `[]` | Image pull secrets for both images. |
| keycloak.authRealm | string | `"master"` | Realm to authenticate against. Almost always `master`. |
| keycloak.url | string | `""` | Base URL of the Keycloak to configure. Point this at the in-cluster Service over plain HTTP: the admin client does not recognise a 308 redirect and fails with an unparseable error if it meets one, and an `http://` URL also removes any truststore question. |
| keycloakImage.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| keycloakImage.registry | string | `"quay.io"` | Image providing `kcadm.sh` for the prune step. Use the same Keycloak version as the server. |
| keycloakImage.repository | string | `"keycloak/keycloak"` | Repository. |
| keycloakImage.tag | string | `"26.7.2"` | Tag. |
| nameOverride | string | `""` | Override the chart name used in resource names and labels. |
| nodeSelector | object | `{}` | Node selector for the jobs. |
| podSecurityContext | object | `{"fsGroup":1000,"runAsGroup":0,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context. |
| priorityClassName | string | `""` | Priority class for the jobs. |
| prune.enabled | bool | `false` | Disable realm users that are absent from `realm.spec`.  config-cli cannot delete users at all — it logs that purging users is not supported. What it does do is enforce roles and group memberships, so a user removed from the file loses their access but keeps a working account. This closes that gap by disabling the account as well. It is off by default because it acts on users this chart never created. |
| prune.exclude | list | `[]` | Usernames never disabled, whatever the realm file says. Keycloak's own `service-account-*` users are always skipped. |
| prune.pageSize | int | `100` | Users fetched per request. The admin API returns 100 at a time and says nothing about the rest, so the script pages explicitly. |
| pruneResources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"50m","memory":"256Mi"}}` | Resources for the prune container. |
| realm.spec | string | `""` | The realm definition, as YAML or JSON text. Supply it by path rather than by hand: `--set-file realm.spec=./realm.yaml` on the CLI, or under Flux a `valuesFrom` entry with `targetPath: realm.spec`. |
| realm.template | bool | `true` | Render `realm.spec` through Helm's template engine first, so it can carry `{{ .Values… }}` references. Keycloak's own `${…}` placeholders and config-cli's `$(env:…)` are untouched by this. |
| reconcile.backoffLimit | int | `2` | Retries before a scheduled run is given up on. |
| reconcile.cache | bool | `false` | Skip the run when the realm file has not changed since the last apply. config-cli stores a checksum on the realm and short-circuits on a match, so leaving this on means the schedule only re-applies after a git change and does NOT correct console drift. Off is what makes it a drift loop. |
| reconcile.enabled | bool | `true` | Re-apply the realm on a schedule, correcting anything changed in the admin console since the last run. |
| reconcile.failedJobsHistoryLimit | int | `3` | Failed jobs kept. |
| reconcile.schedule | string | `"*/15 * * * *"` | Cron schedule for the re-apply. |
| reconcile.startingDeadlineSeconds | int | `300` | Seconds a missed schedule may still start within. |
| reconcile.successfulJobsHistoryLimit | int | `1` | Successful jobs kept. |
| reconcile.timeZone | string | `""` | IANA time zone for the schedule. |
| resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Resources for the config-cli container. |
| serviceAccount.annotations | object | `{}` | Annotations on the ServiceAccount. |
| serviceAccount.create | bool | `true` | Create a ServiceAccount. |
| serviceAccount.name | string | `""` | Name of the ServiceAccount. Generated when empty. |
| substitution.enabled | bool | `true` | Resolve `$(env:NAME)` placeholders in the realm from environment variables. This is how client secrets and user passwords stay out of the realm file. |
| substitution.existingSecret | string | `""` | Secret whose keys become environment variables for the substitution. Every key in it is exposed, so keep it to realm values. |
| substitution.extraEnv | list | `[]` | Extra environment variables for substitution. |
| tolerations | list | `[]` | Tolerations for the jobs. |

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Sophotech s.r.o. |  | <https://sopho.tech> |

## License

Apache-2.0. Copyright 2026 Sophotech s.r.o.

Keycloak™ is a trademark of the Linux Foundation. This chart is not affiliated with, endorsed by, or supported by the Keycloak project.
