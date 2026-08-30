{{/*
Every guard the chart enforces, in one place so a template cannot forget one.
Each fail message is a single line: helm-unittest keeps only the first line of
a render error, so a wrapped message loses the part that names the problem.
*/}}
{{- define "keycloak.validate" -}}
{{- if not .Values.keycloak.hostname }}
{{- fail "keycloak.hostname is required, scheme included, for example https://auth.example.com" }}
{{- end }}
{{- if not (regexMatch "^https?://" .Values.keycloak.hostname) }}
{{- fail (printf "keycloak.hostname must start with http:// or https://, got %q" .Values.keycloak.hostname) }}
{{- end }}
{{- if not .Values.admin.existingSecret }}
{{- fail "admin.existingSecret is required: this chart never generates an admin password, because a generated one changes on every render and locks you out on the next upgrade" }}
{{- end }}
{{- if and (eq .Values.tls.mode "none") (not .Values.keycloak.http.enabled) }}
{{- fail "keycloak.http.enabled is false and tls.mode is none, so nothing would listen on any port" }}
{{- end }}
{{- if and (gt (int .Values.controller.replicas) 1) (eq .Values.cache.mode "local") }}
{{- fail "cache.mode is local with more than one replica, so each pod would keep its own sessions and logins would break at random" }}
{{- end }}
{{- include "keycloak.validateOptimized" . }}
{{- include "keycloak.validateProbes" . }}
{{- end }}

{{/*
Build-time options cannot be set on an optimized image. Keycloak either
ignores them (when they match what was baked) or refuses to start (when they
differ), so silently emitting them is never right.
*/}}
{{- define "keycloak.validateOptimized" -}}
{{- if .Values.keycloak.optimized }}
{{- if .Values.keycloak.features.enabled }}
{{- fail "keycloak.features.enabled is a build-time option and cannot be set when keycloak.optimized is true; bake it into the image with kc.sh build" }}
{{- end }}
{{- if .Values.keycloak.features.disabled }}
{{- fail "keycloak.features.disabled is a build-time option and cannot be set when keycloak.optimized is true; bake it into the image with kc.sh build" }}
{{- end }}
{{- if ne .Values.keycloak.http.relativePath "/" }}
{{- fail "keycloak.http.relativePath is a build-time option and cannot be set when keycloak.optimized is true; bake it into the image with kc.sh build" }}
{{- end }}
{{- if ne .Values.keycloak.management.relativePath "/" }}
{{- fail "keycloak.management.relativePath is a build-time option and cannot be set when keycloak.optimized is true; bake it into the image with kc.sh build" }}
{{- end }}
{{- if ne .Values.keycloak.health.enabled .Values.image.builtWith.healthEnabled }}
{{- fail "keycloak.health.enabled does not match image.builtWith.healthEnabled; health-enabled is a build-time option, so on an optimized image it is decided by the image, not by this value" }}
{{- end }}
{{- if ne .Values.metrics.enabled .Values.image.builtWith.metricsEnabled }}
{{- fail "metrics.enabled does not match image.builtWith.metricsEnabled; metrics-enabled is a build-time option, so on an optimized image it is decided by the image, not by this value" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "keycloak.validateProbes" -}}
{{- $health := eq (include "keycloak.effectiveHealthEnabled" .) "true" }}
{{- if and (not $health) (or .Values.livenessProbe.enabled .Values.readinessProbe.enabled .Values.startupProbe.enabled) }}
{{- fail "probes are enabled but the health endpoints are not; set keycloak.health.enabled or turn the probes off" }}
{{- end }}
{{- if and .Values.metrics.serviceMonitor.enabled (not (eq (include "keycloak.effectiveMetricsEnabled" .) "true")) }}
{{- fail "metrics.serviceMonitor.enabled requires metrics.enabled" }}
{{- end }}
{{- end }}

{{/*
What the running server actually has, which on an optimized image is whatever
the image was built with rather than whatever these values say.
*/}}
{{- define "keycloak.effectiveHealthEnabled" -}}
{{- if .Values.keycloak.optimized -}}
{{- ternary "true" "false" .Values.image.builtWith.healthEnabled -}}
{{- else -}}
{{- ternary "true" "false" .Values.keycloak.health.enabled -}}
{{- end -}}
{{- end }}

{{- define "keycloak.effectiveMetricsEnabled" -}}
{{- if .Values.keycloak.optimized -}}
{{- ternary "true" "false" .Values.image.builtWith.metricsEnabled -}}
{{- else -}}
{{- ternary "true" "false" .Values.metrics.enabled -}}
{{- end -}}
{{- end }}

{{/*
The management interface listens only when health (with management health on)
or metrics is enabled. Getting this wrong points probes and scrapes at a port
nothing is bound to.
*/}}
{{- define "keycloak.managementEnabled" -}}
{{- $health := and (eq (include "keycloak.effectiveHealthEnabled" .) "true") .Values.keycloak.management.healthEnabled -}}
{{- $metrics := eq (include "keycloak.effectiveMetricsEnabled" .) "true" -}}
{{- ternary "true" "false" (or $health $metrics) -}}
{{- end }}

{{/*
Health is served on the management port when management health is on, and on
the main port otherwise.
*/}}
{{- define "keycloak.healthPortName" -}}
{{- if and (eq (include "keycloak.managementEnabled" .) "true") .Values.keycloak.management.healthEnabled -}}
management
{{- else if eq (include "keycloak.httpsEnabled" .) "true" -}}
https
{{- else -}}
http
{{- end -}}
{{- end }}

{{- define "keycloak.healthScheme" -}}
{{- if eq (include "keycloak.healthPortName" .) "management" -}}
{{- if eq .Values.keycloak.management.scheme "http" -}}HTTP{{- else if eq (include "keycloak.httpsEnabled" .) "true" -}}HTTPS{{- else -}}HTTP{{- end -}}
{{- else if eq (include "keycloak.httpsEnabled" .) "true" -}}
HTTPS
{{- else -}}
HTTP
{{- end -}}
{{- end }}

{{- define "keycloak.healthPath" -}}
{{- if eq (include "keycloak.healthPortName" .) "management" -}}
{{- printf "%s/health" (.Values.keycloak.management.relativePath | trimSuffix "/") -}}
{{- else -}}
{{- printf "%s/health" (.Values.keycloak.http.relativePath | trimSuffix "/") -}}
{{- end -}}
{{- end }}
