{{/*
The pod spec, shared by the Deployment and the StatefulSet so the two can
never drift apart.
*/}}
{{- define "keycloak.podSpec" -}}
{{- $tlsSecret := include "keycloak.tlsSecretName" . -}}
serviceAccountName: {{ include "keycloak.serviceAccountName" . }}
automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken }}
terminationGracePeriodSeconds: {{ .Values.controller.terminationGracePeriodSeconds }}
{{- with .Values.image.pullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.extraInitContainers }}
initContainers:
  {{- tpl (toYaml .) $ | nindent 2 }}
{{- end }}
containers:
  - name: keycloak
    image: {{ include "keycloak.image" . }}
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    {{/*
    The image declares an ENTRYPOINT and no CMD, so a pod that omits args
    runs kc.sh with no subcommand, prints usage and exits.
    */}}
    args:
      {{- include "keycloak.args" . | nindent 6 }}
    env:
      {{- include "keycloak.env" . | nindent 6 }}
    {{- with .Values.keycloak.extraEnvFrom }}
    envFrom:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    ports:
      {{- if .Values.keycloak.http.enabled }}
      - name: http
        containerPort: {{ .Values.keycloak.http.port }}
        protocol: TCP
      {{- end }}
      {{- if eq (include "keycloak.httpsEnabled" .) "true" }}
      - name: https
        containerPort: {{ .Values.keycloak.https.port }}
        protocol: TCP
      {{- end }}
      {{- if eq (include "keycloak.managementEnabled" .) "true" }}
      - name: management
        containerPort: {{ .Values.keycloak.management.port }}
        protocol: TCP
      {{- end }}
      {{- if gt (int .Values.controller.replicas) 1 }}
      - name: jgroups
        containerPort: {{ .Values.cache.bindPort }}
        protocol: TCP
      - name: jgroups-fd
        containerPort: {{ add (int .Values.cache.bindPort) 50000 }}
        protocol: TCP
      {{- end }}
    {{- if .Values.startupProbe.enabled }}
    startupProbe:
      httpGet:
        path: {{ include "keycloak.healthPath" . }}/started
        port: {{ include "keycloak.healthPortName" . }}
        scheme: {{ include "keycloak.healthScheme" . }}
      initialDelaySeconds: {{ .Values.startupProbe.initialDelaySeconds }}
      periodSeconds: {{ .Values.startupProbe.periodSeconds }}
      timeoutSeconds: {{ .Values.startupProbe.timeoutSeconds }}
      successThreshold: {{ .Values.startupProbe.successThreshold }}
      failureThreshold: {{ .Values.startupProbe.failureThreshold }}
    {{- end }}
    {{- if .Values.livenessProbe.enabled }}
    livenessProbe:
      httpGet:
        path: {{ include "keycloak.healthPath" . }}/live
        port: {{ include "keycloak.healthPortName" . }}
        scheme: {{ include "keycloak.healthScheme" . }}
      initialDelaySeconds: {{ .Values.livenessProbe.initialDelaySeconds }}
      periodSeconds: {{ .Values.livenessProbe.periodSeconds }}
      timeoutSeconds: {{ .Values.livenessProbe.timeoutSeconds }}
      successThreshold: {{ .Values.livenessProbe.successThreshold }}
      failureThreshold: {{ .Values.livenessProbe.failureThreshold }}
    {{- end }}
    {{- if .Values.readinessProbe.enabled }}
    readinessProbe:
      httpGet:
        path: {{ include "keycloak.healthPath" . }}/ready
        port: {{ include "keycloak.healthPortName" . }}
        scheme: {{ include "keycloak.healthScheme" . }}
      initialDelaySeconds: {{ .Values.readinessProbe.initialDelaySeconds }}
      periodSeconds: {{ .Values.readinessProbe.periodSeconds }}
      timeoutSeconds: {{ .Values.readinessProbe.timeoutSeconds }}
      successThreshold: {{ .Values.readinessProbe.successThreshold }}
      failureThreshold: {{ .Values.readinessProbe.failureThreshold }}
    {{- end }}
    {{- with .Values.containerSecurityContext }}
    securityContext:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    volumeMounts:
      {{- if $tlsSecret }}
      - name: keycloak-tls
        mountPath: /opt/keycloak/certs
        readOnly: true
      {{- end }}
      {{- with .Values.extraVolumeMounts }}
      {{- tpl (toYaml .) $ | nindent 6 }}
      {{- end }}
  {{- with .Values.extraContainers }}
  {{- tpl (toYaml .) $ | nindent 2 }}
  {{- end }}
volumes:
  {{- if $tlsSecret }}
  - name: keycloak-tls
    secret:
      secretName: {{ $tlsSecret }}
  {{- end }}
  {{- with .Values.extraVolumes }}
  {{- tpl (toYaml .) $ | nindent 2 }}
  {{- end }}
{{- end }}

{{/*
Arguments to kc.sh. Build-time options are emitted only on a non-optimized
start; on an optimized image they are baked in and passing them is at best
ignored and at worst fatal.
*/}}
{{- define "keycloak.args" -}}
- start
{{- if .Values.keycloak.optimized }}
- --optimized
{{- end }}
- --hostname={{ .Values.keycloak.hostname }}
{{- with .Values.keycloak.hostnameAdmin }}
- --hostname-admin={{ . }}
{{- end }}
- --hostname-strict={{ .Values.keycloak.hostnameStrict }}
{{- if .Values.keycloak.hostnameBackchannelDynamic }}
- --hostname-backchannel-dynamic=true
{{- end }}
{{- with .Values.keycloak.proxyHeaders }}
- --proxy-headers={{ . }}
{{- end }}
{{- with .Values.keycloak.proxyTrustedAddresses }}
- --proxy-trusted-addresses={{ . }}
{{- end }}
- --http-enabled={{ .Values.keycloak.http.enabled }}
- --http-port={{ .Values.keycloak.http.port }}
{{- if eq (include "keycloak.httpsEnabled" .) "true" }}
- --https-port={{ .Values.keycloak.https.port }}
- --https-certificate-file=/opt/keycloak/certs/tls.crt
- --https-certificate-key-file=/opt/keycloak/certs/tls.key
{{- end }}
{{- if eq (include "keycloak.managementEnabled" .) "true" }}
- --http-management-scheme={{ .Values.keycloak.management.scheme }}
{{- end }}
- --db-url={{ include "keycloak.databaseUrl" . }}
{{- with .Values.cache.mode }}
- --cache={{ . }}
{{- end }}
{{- with .Values.cache.stack }}
- --cache-stack={{ . }}
{{- end }}
{{- with .Values.cache.configFile }}
- --cache-config-file={{ . }}
{{- end }}
{{- if not .Values.cache.mtls.enabled }}
- --cache-embedded-mtls-enabled=false
{{- end }}
{{- if not .Values.keycloak.optimized }}
- --db=postgres
- --health-enabled={{ .Values.keycloak.health.enabled }}
- --metrics-enabled={{ .Values.metrics.enabled }}
{{- if not .Values.keycloak.management.healthEnabled }}
- --http-management-health-enabled=false
{{- end }}
{{- if ne .Values.keycloak.http.relativePath "/" }}
- --http-relative-path={{ .Values.keycloak.http.relativePath }}
{{- end }}
{{- if ne .Values.keycloak.management.relativePath "/" }}
- --http-management-relative-path={{ .Values.keycloak.management.relativePath }}
{{- end }}
{{/*
An empty --features= is a real value from a real config source and will not
match a persisted absence, so it is emitted only when there is something to
put in it.
*/}}
{{- with .Values.keycloak.features.enabled }}
- --features={{ join "," . }}
{{- end }}
{{- with .Values.keycloak.features.disabled }}
- --features-disabled={{ join "," . }}
{{- end }}
{{- end }}
{{- with .Values.keycloak.extraArgs }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Environment. POD_IP has to come first: Kubernetes expands $(VAR) only from
entries defined earlier in the same container, and passes an undefined
reference through as a literal string.
*/}}
{{- define "keycloak.env" -}}
{{- if and (gt (int .Values.controller.replicas) 1) .Values.cache.bindToPodIP }}
- name: POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
- name: KC_CACHE_EMBEDDED_NETWORK_BIND_ADDRESS
  value: "$(POD_IP)"
{{- end }}
{{- if .Values.admin.usernameKey }}
- name: KC_BOOTSTRAP_ADMIN_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.admin.existingSecret }}
      key: {{ .Values.admin.usernameKey }}
{{- else }}
- name: KC_BOOTSTRAP_ADMIN_USERNAME
  value: {{ .Values.admin.username | quote }}
{{- end }}
- name: KC_BOOTSTRAP_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.admin.existingSecret }}
      key: {{ .Values.admin.passwordKey }}
- name: KC_DB_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ include "keycloak.databaseSecretName" . }}
      key: {{ .Values.database.secretKeys.usernameKey }}
- name: KC_DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "keycloak.databaseSecretName" . }}
      key: {{ .Values.database.secretKeys.passwordKey }}
{{- with .Values.keycloak.extraEnv }}
{{- tpl (toYaml .) $ }}
{{- end }}
{{- end }}

{{- define "keycloak.databaseUrl" -}}
{{- $url := printf "jdbc:postgresql://%s:%v/%s" (include "keycloak.databaseHost" .) (include "keycloak.databasePort" .) (include "keycloak.databaseName" .) -}}
{{- with .Values.database.extraParams -}}
{{- $url = printf "%s?%s" $url . -}}
{{- end -}}
{{- $url -}}
{{- end }}
