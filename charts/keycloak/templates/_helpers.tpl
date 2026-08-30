{{/*
Chart name, overridable.
*/}}
{{- define "keycloak.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified release name.
*/}}
{{- define "keycloak.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "keycloak.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "keycloak.labels" -}}
helm.sh/chart: {{ include "keycloak.chart" . }}
{{ include "keycloak.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: keycloak
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "keycloak.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "keycloak.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "keycloak.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container image reference. A digest, when set, wins over the tag but both are
emitted so the tag stays readable in `kubectl describe`.
*/}}
{{- define "keycloak.image" -}}
{{- $registry := .Values.image.registry -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- $ref := printf "%s:%s" $repository $tag -}}
{{- if $registry -}}
{{- $ref = printf "%s/%s" $registry $ref -}}
{{- end -}}
{{- if .Values.image.digest -}}
{{- $ref = printf "%s@%s" $ref .Values.image.digest -}}
{{- end -}}
{{- $ref -}}
{{- end }}

{{- define "keycloak.headlessServiceName" -}}
{{- printf "%s-headless" (include "keycloak.fullname" .) }}
{{- end }}

{{- define "keycloak.metricsServiceName" -}}
{{- printf "%s-metrics" (include "keycloak.fullname" .) }}
{{- end }}

{{- define "keycloak.databaseClusterName" -}}
{{- printf "%s-pg" (include "keycloak.fullname" .) }}
{{- end }}

{{/*
Database host. In cnpg mode this is the read-write service CloudNativePG
creates beside the Cluster; in external mode the operator supplies it.
*/}}
{{- define "keycloak.databaseHost" -}}
{{- if eq .Values.database.mode "cnpg" -}}
{{- printf "%s-rw" (include "keycloak.databaseClusterName" .) -}}
{{- else -}}
{{- required "database.host is required when database.mode is external" .Values.database.host -}}
{{- end -}}
{{- end }}

{{/*
Secret holding the database username and password. CloudNativePG generates
<cluster>-app itself; it is never rendered by this chart.
*/}}
{{- define "keycloak.databaseSecretName" -}}
{{- if eq .Values.database.mode "cnpg" -}}
{{- printf "%s-app" (include "keycloak.databaseClusterName" .) -}}
{{- else -}}
{{- required "database.existingSecret is required when database.mode is external" .Values.database.existingSecret -}}
{{- end -}}
{{- end }}

{{- define "keycloak.databaseName" -}}
{{- if eq .Values.database.mode "cnpg" -}}
{{- .Values.database.cnpg.database -}}
{{- else -}}
{{- .Values.database.name -}}
{{- end -}}
{{- end }}

{{- define "keycloak.databasePort" -}}
{{- if eq .Values.database.mode "cnpg" -}}
5432
{{- else -}}
{{- .Values.database.port -}}
{{- end -}}
{{- end }}

{{/*
Secret holding tls.crt and tls.key for the server's own HTTPS listener.
Empty when TLS is not terminated by Keycloak itself.
*/}}
{{- define "keycloak.tlsSecretName" -}}
{{- if eq .Values.tls.mode "cert-manager" -}}
{{- printf "%s-tls" (include "keycloak.fullname" .) -}}
{{- else if eq .Values.tls.mode "existingSecret" -}}
{{- required "tls.existingSecret is required when tls.mode is existingSecret" .Values.tls.existingSecret -}}
{{- end -}}
{{- end }}

{{- define "keycloak.httpsEnabled" -}}
{{- if ne .Values.tls.mode "none" -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
Service port Keycloak is reached on, which follows from whether it terminates
TLS itself. Routes and probes both derive from this rather than repeating it.
*/}}
{{- define "keycloak.servicePort" -}}
{{- if eq (include "keycloak.httpsEnabled" .) "true" -}}
{{- .Values.service.ports.https -}}
{{- else -}}
{{- .Values.service.ports.http -}}
{{- end -}}
{{- end }}

{{- define "keycloak.serviceScheme" -}}
{{- if eq (include "keycloak.httpsEnabled" .) "true" -}}https{{- else -}}http{{- end -}}
{{- end }}

{{/*
Host without the scheme, for route objects that want a bare hostname.
*/}}
{{- define "keycloak.hostname" -}}
{{- $h := required "keycloak.hostname is required" .Values.keycloak.hostname -}}
{{- $h | trimPrefix "https://" | trimPrefix "http://" | trimSuffix "/" -}}
{{- end }}
