# keycloak

Keycloak, with its database, certificate, route and backups optional rather than assumed

![Version: 0.0.0](https://img.shields.io/badge/Version-0.0.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 26.7.2](https://img.shields.io/badge/AppVersion-26.7.2-informational?style=flat-square)

## Install

```sh
helm install keycloak oci://ghcr.io/sophotechlabs/charts/keycloak \
  --set keycloak.hostname=https://auth.example.com \
  --set admin.existingSecret=keycloak-admin
```

## What it creates, and what it does not

Four things this chart can create for you are each behind a mode value, and each defaults to off or to the least opinionated option. Nothing is auto-detected: a chart that renders differently depending on which CRDs happen to be installed renders differently under `helm template`, under a Flux dry-run, and in your cluster.

| Value | Options | Default |
|---|---|---|
| `database.mode` | `cnpg` creates a CloudNativePG `Cluster`; `external` uses a database you already have | `cnpg` |
| `tls.mode` | `cert-manager` issues a `Certificate`; `existingSecret` uses yours; `none` leaves TLS to whatever is in front | `none` |
| `route.mode` | `traefik`, `ingress`, `gateway`, `none` | `none` |
| `backup.mode` | `pgdump` runs a periodic dump into a volume; `none` | `none` |

With all four at their defaults except a database, the chart installs on a cluster with no CRDs at all. That path is tested in CI on a kind cluster with none of them installed.

The one thing that is not optional is a database — the only choice is who creates it.

## Things worth knowing before you run it

**The admin password is never generated.** `admin.existingSecret` is required. A chart-generated password changes on every render and locks you out on the next upgrade.

**`controller.kind` decides how upgrades roll.** Keycloak migrates its database schema on start, so a `StatefulSet` (the default) rolling one pod at a time is the safe shape. The `Deployment` branch defaults to `strategy: Recreate` for the same reason. Switching between the two on a live release replaces the object rather than updating it.

**Clustering needs no configuration.** Keycloak 26 discovers its peers through the database, so `controller.replicas: 3` works as-is. Do not set `cache.stack: kubernetes` — that path is deprecated upstream and needs a system property with no CLI equivalent.

If you run more than one replica against an *external* database, note that a second Keycloak release pointed at the same database and schema will merge into the same cluster. Give each release its own database or schema.

**`keycloak.optimized` requires a matching image.** Keycloak's `health-enabled`, `metrics-enabled`, `features` and `http-relative-path` are build-time options: on an image built with `kc.sh build` they are baked in, and passing them at runtime is either ignored or fatal. With `optimized: true` the chart refuses to emit them and checks your `image.builtWith` declarations against the values that depend on them, rather than silently producing probes pointing at a port nothing is listening on.

**Probes follow the management port.** Health and metrics live on port 9000, which listens only when health or metrics is enabled. `keycloak.management.scheme` defaults to `http` so kubelet probes stay plain even when Keycloak terminates TLS; set it to `inherited` if you want the management port to follow the main listener, and the probes will follow.

## Realm and user configuration

This chart runs the server. To keep a realm — clients, roles, groups and users — matching a file in git, use [`keycloak-config`](../keycloak-config).

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| admin.existingSecret | string | `""` | Secret holding the bootstrap admin credentials. Required. This chart never generates a password: a generated one changes on every render and locks you out on the next upgrade. |
| admin.passwordKey | string | `"password"` | Key in that secret holding the password. |
| admin.username | string | `"temp-admin"` | Bootstrap admin username, used when the secret carries only a password. Keycloak's own default is `temp-admin`. The bootstrap account applies only while the master realm does not exist yet. |
| admin.usernameKey | string | `""` | Key in that secret holding the username. Empty uses `admin.username` as a literal instead, which is the common case. |
| affinity | object | `{}` | Affinity for Keycloak pods. |
| backup.backoffLimit | int | `2` | Retries before a dump is given up on. |
| backup.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | Container security context for the dump. |
| backup.extraEnv | list | `[]` | Extra environment variables for the dump container. |
| backup.failedJobsHistoryLimit | int | `3` | Failed jobs kept. |
| backup.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| backup.image.repository | string | `"ghcr.io/cloudnative-pg/postgresql"` | Image carrying `pg_dump`. Its major version must be at least the server's. |
| backup.image.tag | string | `"18.4-system-trixie"` | Image tag. |
| backup.mode | string | `"none"` | `pgdump` runs a periodic `pg_dump` into a volume; `none` creates nothing. In `cnpg` database mode, `database.cnpg.backup` is the object-store alternative and the two are independent. |
| backup.nodeSelector | object | `{}` | Node selector for the dump. |
| backup.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes for the created claim. |
| backup.persistence.existingClaim | string | `""` | Use an existing claim instead of creating one. |
| backup.persistence.size | string | `"4Gi"` | Size of the created claim. |
| backup.persistence.storageClass | string | `""` | Storage class for the created claim. |
| backup.podSecurityContext | object | `{"fsGroup":26,"runAsGroup":26,"runAsNonRoot":true,"runAsUser":26,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context for the dump. |
| backup.priorityClassName | string | `""` | Priority class for the dump. |
| backup.resources | object | `{"limits":{"memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}` | Resources for the dump container. |
| backup.retain | int | `7` | Dumps to keep. |
| backup.schedule | string | `"0 3 * * *"` | Cron schedule for the dump. |
| backup.startingDeadlineSeconds | int | `300` | Seconds a missed schedule may still start within. |
| backup.successfulJobsHistoryLimit | int | `3` | Successful jobs kept. |
| backup.timeZone | string | `""` | IANA time zone for the schedule. |
| backup.tolerations | list | `[]` | Tolerations for the dump. |
| backup.waitForDatabaseAttempts | int | `90` | Two-second waits for the database before dumping. |
| cache.bindPort | int | `7800` | JGroups bind port. The failure-detection port is this plus 50000, and the NetworkPolicy computes it rather than hardcoding 57800. |
| cache.bindToPodIP | bool | `true` | Bind the JGroups transport to the pod IP rather than letting JGroups pick by `SITE_LOCAL`, which misses pod CIDRs outside RFC1918. |
| cache.configFile | string | `""` | Path to a custom Infinispan XML, relative to `conf/`. |
| cache.mode | string | `""` | `ispn` or `local`, or empty to let Keycloak decide. Keycloak picks `ispn` when running as a server. |
| cache.mtls.enabled | bool | `true` | Encrypt and authenticate cluster traffic. Keycloak's default is true. |
| cache.stack | string | `""` | JGroups discovery stack. Empty means `jdbc-ping`, which discovers peers through the database and needs no extra configuration — which is why this chart leaves it empty. `kubernetes` is deprecated upstream and needs a system property with no CLI equivalent. |
| commonAnnotations | object | `{}` | Annotations added to every object this chart creates. |
| commonLabels | object | `{}` | Labels added to every object this chart creates. |
| containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":false}` | Container security context. `readOnlyRootFilesystem` is false because a non-optimized start writes the augmentation output under `/opt/keycloak/lib/quarkus`. With `keycloak.optimized: true` you can set it true. |
| controller.annotations | object | `{}` | Annotations on the controller object. |
| controller.kind | string | `"StatefulSet"` | `StatefulSet` or `Deployment`. StatefulSet rolls one pod at a time, which matters because Keycloak migrates the database schema on start; a Deployment's default surge would run the new and old versions against the same database at once. Switching this on a live release replaces the object rather than updating it. |
| controller.podAnnotations | object | `{}` | Annotations on the pod template. |
| controller.podLabels | object | `{}` | Labels on the pod template. |
| controller.podManagementPolicy | string | `"OrderedReady"` | StatefulSet pod management policy. `OrderedReady` is what makes an upgrade strictly sequential. |
| controller.replicas | int | `1` | Number of Keycloak pods. |
| controller.revisionHistoryLimit | int | `10` | Revision history kept by the controller. |
| controller.strategy | object | `{"type":"Recreate"}` | Deployment `strategy`. Defaults to `Recreate`, for the schema-migration reason above. Ignored for a StatefulSet. |
| controller.terminationGracePeriodSeconds | int | `60` | Seconds a pod gets to shut down cleanly. |
| controller.updateStrategy | object | `{}` | StatefulSet `updateStrategy`. Ignored for a Deployment. |
| database.cnpg.affinity | object | `{}` | Affinity for the PostgreSQL pods. |
| database.cnpg.backup | object | `{}` | CloudNativePG `backup` block, for Barman object-store backups. |
| database.cnpg.database | string | `"keycloak"` | Database created at bootstrap. |
| database.cnpg.imageCatalogRef | object | `{}` | CloudNativePG `imageCatalogRef`. |
| database.cnpg.imageName | string | `""` | Explicit PostgreSQL image. Empty uses the operator's default. |
| database.cnpg.initdb | object | `{}` | Extra `bootstrap.initdb` fields. |
| database.cnpg.instances | int | `1` | PostgreSQL instances in the cluster. |
| database.cnpg.owner | string | `"keycloak"` | Role owning that database. |
| database.cnpg.podMonitor.enabled | bool | `false` | Create a PodMonitor for the PostgreSQL pods. |
| database.cnpg.podMonitor.interval | string | `""` | Scrape interval. |
| database.cnpg.podMonitor.labels | object | `{}` | Extra labels for that PodMonitor. |
| database.cnpg.postgresql | object | `{}` | `postgresql` block passed through to the Cluster. |
| database.cnpg.priorityClassName | string | `""` | Priority class for the PostgreSQL pods. |
| database.cnpg.resources | object | `{}` | Resources for the PostgreSQL pods. |
| database.cnpg.retainOnDelete | bool | `true` | Keep the Cluster and its volumes when the release is uninstalled. |
| database.cnpg.storage.size | string | `"8Gi"` | Volume size for each instance. |
| database.cnpg.storage.storageClass | string | `""` | Storage class for the data volume. |
| database.cnpg.walStorage | object | `{}` | Separate WAL storage. |
| database.existingSecret | string | `""` | Secret holding the database username and password. Required when mode is `external`. |
| database.extraParams | string | `""` | Extra JDBC parameters appended to the connection URL. |
| database.host | string | `""` | Database host. Required when mode is `external`. |
| database.mode | string | `"cnpg"` | `cnpg` creates a CloudNativePG `Cluster` and reads the credentials CloudNativePG generates. `external` points at a database you already have. |
| database.name | string | `"keycloak"` | Database name. Used when mode is `external`. |
| database.port | int | `5432` | Database port. Used when mode is `external`. |
| database.secretKeys.passwordKey | string | `"password"` | Key in the database secret holding the password. |
| database.secretKeys.usernameKey | string | `"username"` | Key in the database secret holding the username. |
| extraContainers | list | `[]` | Extra sidecar containers. |
| extraInitContainers | list | `[]` | Extra init containers. |
| extraObjects | list | `[]` | Arbitrary extra manifests, rendered through `tpl`. |
| extraVolumeMounts | list | `[]` | Extra volume mounts on the Keycloak container. |
| extraVolumes | list | `[]` | Extra volumes on the pod. |
| fullnameOverride | string | `""` | Override the full release-qualified name used for every resource. |
| image.builtWith.healthEnabled | bool | `true` | Whether the image was built with `--health-enabled=true`. Only read when `keycloak.optimized` is true. `health-enabled` is a Keycloak build-time option, so on an optimized image it cannot be turned on at runtime — declaring it wrong here means probes point at a dark port. |
| image.builtWith.metricsEnabled | bool | `true` | Whether the image was built with `--metrics-enabled=true`. Only read when `keycloak.optimized` is true. |
| image.digest | string | `""` | Image digest, `sha256:…`. Appended to the tag when set, and it is the digest that decides which bytes run. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.pullSecrets | list | `[]` | Image pull secrets. |
| image.registry | string | `"quay.io"` | Registry serving the Keycloak image. |
| image.repository | string | `"keycloak/keycloak"` | Keycloak image repository. |
| image.tag | string | `""` | Image tag. Defaults to the chart's appVersion when empty. |
| keycloak.extraArgs | list | `[]` | Extra arguments appended after `start`. |
| keycloak.extraEnv | list | `[]` | Extra environment variables for the Keycloak container. |
| keycloak.extraEnvFrom | list | `[]` | Extra `envFrom` sources for the Keycloak container. |
| keycloak.features.disabled | list | `[]` | Keycloak features to disable. Build-time. |
| keycloak.features.enabled | list | `[]` | Keycloak features to enable. Build-time. |
| keycloak.health.enabled | bool | `true` | Enable the health endpoints at all. Build-time, and Keycloak's own default is false. |
| keycloak.hostname | string | `""` | Public URL Keycloak serves on, scheme included, e.g. `https://auth.example.com`. Required: Keycloak builds issuer URLs and redirect targets from it. |
| keycloak.hostnameAdmin | string | `""` | Separate URL for the admin console, when it is not the same host. |
| keycloak.hostnameBackchannelDynamic | bool | `false` | Resolve backchannel URLs from the incoming request instead of `hostname`. Needed when in-cluster clients talk to the Service directly. |
| keycloak.hostnameStrict | bool | `true` | Reject requests whose Host header does not match `hostname`. |
| keycloak.http.enabled | bool | `true` | Serve plain HTTP. Keycloak's own default is false, and a pod behind a TLS-terminating proxy needs this on or nothing listens on 8080. |
| keycloak.http.port | int | `8080` | HTTP container port. |
| keycloak.http.relativePath | string | `"/"` | Path Keycloak is served under. Build-time: it must match the image when `keycloak.optimized` is true. |
| keycloak.https.port | int | `8443` | HTTPS container port. Serving HTTPS is driven by `tls.mode`, not by a switch here. |
| keycloak.management.healthEnabled | bool | `true` | Serve health on the management port. Build-time. Turning it off moves health onto the main HTTP port. |
| keycloak.management.port | int | `9000` | Management container port, carrying health and metrics. |
| keycloak.management.relativePath | string | `"/"` | Path the management endpoints are served under. Build-time. |
| keycloak.management.scheme | string | `"http"` | `http` or `inherited`. `inherited` follows the main listener, so the management port turns HTTPS the moment TLS is configured and kubelet probes then need HTTPS too. `http` keeps probes plain and is why it is the default here. |
| keycloak.optimized | bool | `false` |  |
| keycloak.proxyHeaders | string | `""` | Which proxy headers to trust: `forwarded`, `xforwarded`, or empty for none. Leaving this empty behind a reverse proxy makes Keycloak generate URLs from its own address rather than the public one. |
| keycloak.proxyTrustedAddresses | string | `""` | Trusted proxy addresses, comma separated. |
| livenessProbe.enabled | bool | `true` | Enable the liveness probe. Requires the health endpoints. |
| livenessProbe.failureThreshold | int | `3` | Consecutive failures tolerated. |
| livenessProbe.initialDelaySeconds | int | `60` | Seconds before the first probe. |
| livenessProbe.periodSeconds | int | `30` | Seconds between probes. |
| livenessProbe.successThreshold | int | `1` | Consecutive successes needed. |
| livenessProbe.timeoutSeconds | int | `5` | Probe timeout. |
| metrics.enabled | bool | `false` | Enable Keycloak's metrics endpoint. Build-time: on an optimized image this must match how the image was built. |
| metrics.path | string | `"/metrics"` | Path metrics are served on, under the management relative path. |
| metrics.service.annotations | object | `{}` | Annotations on the management Service. |
| metrics.serviceMonitor.enabled | bool | `false` | Create a ServiceMonitor. Needs the Prometheus operator CRDs. |
| metrics.serviceMonitor.interval | string | `""` | Scrape interval. |
| metrics.serviceMonitor.labels | object | `{}` | Extra labels, usually what a Prometheus instance selects on. |
| metrics.serviceMonitor.metricRelabelings | list | `[]` | Metric relabeling rules. |
| metrics.serviceMonitor.namespace | string | `""` | Namespace for the ServiceMonitor. Defaults to the release namespace. |
| metrics.serviceMonitor.relabelings | list | `[]` | Relabeling rules. |
| metrics.serviceMonitor.scrapeTimeout | string | `""` | Scrape timeout. |
| metrics.serviceMonitor.tlsConfig | object | `{}` | TLS config for the scrape. |
| nameOverride | string | `""` | Override the chart name used in resource names and labels. |
| networkPolicy.egress.enabled | bool | `false` | Restrict egress as well. Leaving this off avoids breaking database and DNS traffic by omission. |
| networkPolicy.egress.rules | list | `[]` | Egress rules, used only when egress is enabled. |
| networkPolicy.enabled | bool | `false` | Create a NetworkPolicy. |
| networkPolicy.extraIngress | list | `[]` | Extra ingress rules. |
| networkPolicy.ingress.from | list | `[]` | Peers allowed to reach the HTTP and HTTPS ports. Empty allows all. |
| networkPolicy.ingress.metricsFrom | list | `[]` | Peers allowed to reach the management port. Empty allows all. |
| nodeSelector | object | `{}` | Node selector for Keycloak pods. |
| podDisruptionBudget.enabled | bool | `false` | Create a PodDisruptionBudget. |
| podDisruptionBudget.maxUnavailable | string | `""` | Maximum unavailable pods. |
| podDisruptionBudget.minAvailable | string | `""` | Minimum available pods. Rejected with a single replica, where it would block every node drain. |
| podSecurityContext | object | `{"fsGroup":1000,"runAsGroup":0,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context. |
| priorityClassName | string | `""` | Priority class for Keycloak pods. |
| readinessProbe.enabled | bool | `true` | Enable the readiness probe. |
| readinessProbe.failureThreshold | int | `3` | Consecutive failures tolerated. |
| readinessProbe.initialDelaySeconds | int | `30` | Seconds before the first probe. |
| readinessProbe.periodSeconds | int | `10` | Seconds between probes. |
| readinessProbe.successThreshold | int | `1` | Consecutive successes needed. |
| readinessProbe.timeoutSeconds | int | `5` | Probe timeout. |
| resources | object | `{"limits":{"memory":"2Gi"},"requests":{"cpu":"250m","memory":"768Mi"}}` | Resources for the Keycloak container. A non-optimized start runs an augmentation step on boot, which is CPU-hungry for a few seconds. |
| route.gateway.annotations | object | `{}` | Annotations on the HTTPRoute. |
| route.gateway.extraHostnames | list | `[]` | Extra hostnames on the HTTPRoute. |
| route.gateway.filters | list | `[]` | Filters applied to the rule. |
| route.gateway.parentRefs | list | `[]` | `parentRefs` for the HTTPRoute. Required when mode is `gateway`. |
| route.gateway.path.type | string | `"PathPrefix"` | Path match type. |
| route.gateway.path.value | string | `"/"` | Path match value. |
| route.ingress.annotations | object | `{}` | Annotations on the Ingress. |
| route.ingress.className | string | `""` | IngressClass name. |
| route.ingress.extraHosts | list | `[]` | Extra hosts, each `{host, path, pathType}`. |
| route.ingress.path | string | `"/"` | Path matched by the rule. |
| route.ingress.pathType | string | `"Prefix"` | Path type. |
| route.ingress.tls | list | `[]` | `tls` block on the Ingress. |
| route.mode | string | `"none"` | `traefik`, `ingress`, `gateway` or `none`. |
| route.traefik.annotations | object | `{}` | Annotations on the IngressRoute. |
| route.traefik.entryPoints | list | `["websecure"]` | Traefik entry points to attach the route to. |
| route.traefik.middlewares | list | `[]` | Middlewares applied to the route. |
| route.traefik.priority | string | `""` | Route priority. |
| route.traefik.serversTransport.create | bool | `true` | Create a ServersTransport. Only needed when Keycloak terminates TLS itself, because Traefik then has to trust its certificate. |
| route.traefik.serversTransport.insecureSkipVerify | bool | `true` | Skip verification of Keycloak's certificate. |
| route.traefik.serversTransport.name | string | `""` | Use an existing ServersTransport instead of creating one. |
| route.traefik.serversTransport.rootCAsSecret | string | `""` | Secret with the CA bundle, when not skipping verification. |
| route.traefik.tls | object | `{}` | `tls` block on the IngressRoute. `{}` uses the default certificate. |
| service.annotations | object | `{}` | Annotations on the Service. |
| service.clusterIP | string | `""` | Explicit clusterIP. |
| service.nodePorts.http | string | `""` | Node port for HTTP, when type is NodePort. |
| service.nodePorts.https | string | `""` | Node port for HTTPS, when type is NodePort. |
| service.ports.http | int | `8080` | HTTP service port. |
| service.ports.https | int | `8443` | HTTPS service port. |
| service.sessionAffinity | string | `""` | Session affinity. |
| service.type | string | `"ClusterIP"` | Service type. |
| serviceAccount.annotations | object | `{}` | Annotations on the ServiceAccount. |
| serviceAccount.automountServiceAccountToken | bool | `false` | Mount the API token. Keycloak does not call the API, so this is off. |
| serviceAccount.create | bool | `true` | Create a ServiceAccount for Keycloak. |
| serviceAccount.name | string | `""` | Name of the ServiceAccount. Generated when empty. |
| startupProbe.enabled | bool | `true` | Enable the startup probe. A non-optimized start builds on boot, so the window has to cover that. |
| startupProbe.failureThreshold | int | `60` | Consecutive failures tolerated. |
| startupProbe.initialDelaySeconds | int | `15` | Seconds before the first probe. |
| startupProbe.periodSeconds | int | `5` | Seconds between probes. |
| startupProbe.successThreshold | int | `1` | Consecutive successes needed. |
| startupProbe.timeoutSeconds | int | `5` | Probe timeout. |
| tests.enabled | bool | `true` | Render the `helm test` pod. |
| tests.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| tests.image.repository | string | `"curlimages/curl"` | Image used by the test pod. |
| tests.image.tag | string | `"8.18.0"` | Image tag. |
| tls.certManager.dnsNames | list | `[]` | DNS names on the certificate. Empty means the in-cluster Service names, which is what secures the proxy-to-Keycloak hop. |
| tls.certManager.duration | string | `""` | Certificate lifetime. |
| tls.certManager.issuerRef.group | string | `""` | Issuer API group. |
| tls.certManager.issuerRef.kind | string | `"ClusterIssuer"` | `Issuer` or `ClusterIssuer`. |
| tls.certManager.issuerRef.name | string | `""` | Issuer name. Required when mode is `cert-manager`. |
| tls.certManager.privateKey | object | `{}` | `privateKey` block passed to the Certificate. |
| tls.certManager.renewBefore | string | `""` | How long before expiry to renew. |
| tls.existingSecret | string | `""` | Secret with `tls.crt` and `tls.key`. Required when mode is `existingSecret`. |
| tls.mode | string | `"none"` | `cert-manager` issues a Certificate and Keycloak terminates TLS itself; `existingSecret` uses a secret you supply; `none` serves plain HTTP and leaves TLS to whatever is in front. |
| tolerations | list | `[]` | Tolerations for Keycloak pods. |
| topologySpreadConstraints | list | `[]` | Topology spread constraints for Keycloak pods. |

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Sophotech s.r.o. |  | <https://sopho.tech> |

## License

Apache-2.0. Copyright 2026 Sophotech s.r.o.

Keycloak™ is a trademark of the Linux Foundation. This chart is not affiliated with, endorsed by, or supported by the Keycloak project.
