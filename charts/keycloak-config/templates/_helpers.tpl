{{- define "keycloak-config.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "keycloak-config.fullname" -}}
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

{{- define "keycloak-config.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "keycloak-config.labels" -}}
helm.sh/chart: {{ include "keycloak-config.chart" . }}
{{ include "keycloak-config.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: keycloak
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "keycloak-config.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak-config.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "keycloak-config.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "keycloak-config.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
The realm definition as text, optionally rendered through Helm first. Keycloak's
own ${…} placeholders and config-cli's $(env:…) both survive that pass.
*/}}
{{- define "keycloak-config.realmText" -}}
{{- if .Values.realm.template -}}
{{- tpl .Values.realm.spec . -}}
{{- else -}}
{{- .Values.realm.spec -}}
{{- end -}}
{{- end }}

{{/*
Short hash of the realm, used in the apply job's name so a changed realm makes
a new job instead of trying to patch a job spec Kubernetes will not let you
change.
*/}}
{{- define "keycloak-config.realmHash" -}}
{{- include "keycloak-config.realmText" . | sha256sum | trunc 10 -}}
{{- end }}

{{- define "keycloak-config.realmName" -}}
{{- $realm := fromYaml (include "keycloak-config.realmText" .) -}}
{{- $realm.realm -}}
{{- end }}

{{- define "keycloak-config.configCliImage" -}}
{{- $registry := .Values.configCli.image.registry -}}
{{- $ref := printf "%s:%s" .Values.configCli.image.repository .Values.configCli.image.tag -}}
{{- if $registry -}}
{{- printf "%s/%s" $registry $ref -}}
{{- else -}}
{{- $ref -}}
{{- end -}}
{{- end }}

{{- define "keycloak-config.keycloakImage" -}}
{{- $registry := .Values.keycloakImage.registry -}}
{{- $ref := printf "%s:%s" .Values.keycloakImage.repository .Values.keycloakImage.tag -}}
{{- if $registry -}}
{{- printf "%s/%s" $registry $ref -}}
{{- else -}}
{{- $ref -}}
{{- end -}}
{{- end }}

{{- define "keycloak-config.realmSecretName" -}}
{{- printf "%s-realm" (include "keycloak-config.fullname" .) }}
{{- end }}

{{- define "keycloak-config.envConfigMapName" -}}
{{- printf "%s-env" (include "keycloak-config.fullname" .) }}
{{- end }}

{{- define "keycloak-config.pruneConfigMapName" -}}
{{- printf "%s-prune" (include "keycloak-config.fullname" .) }}
{{- end }}
