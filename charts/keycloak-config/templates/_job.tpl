{{/*
Pod spec shared by the apply Job and the reconcile CronJob, so the scheduled
run and the install-time run can never do different things.

When pruning is on, config-cli runs as an init container and the prune script
as the main one: an init container is guaranteed to finish first, whereas two
containers in the same pod would race.
*/}}
{{- define "keycloak-config.jobPodSpec" -}}
restartPolicy: Never
serviceAccountName: {{ include "keycloak-config.serviceAccountName" . }}
automountServiceAccountToken: false
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
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
{{- with .Values.priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
{{- if .Values.prune.enabled }}
initContainers:
  {{- include "keycloak-config.configCliContainer" . | nindent 2 }}
containers:
  {{- include "keycloak-config.pruneContainer" . | nindent 2 }}
{{- else }}
containers:
  {{- include "keycloak-config.configCliContainer" . | nindent 2 }}
{{- end }}
volumes:
  - name: realm
    secret:
      secretName: {{ include "keycloak-config.realmSecretName" . }}
  - name: tmp
    emptyDir: {}
  {{- if .Values.prune.enabled }}
  - name: prune
    configMap:
      name: {{ include "keycloak-config.pruneConfigMapName" . }}
      defaultMode: 0555
  {{- end }}
  {{- with .Values.extraVolumes }}
  {{- tpl (toYaml .) $ | nindent 2 }}
  {{- end }}
{{- end }}

{{- define "keycloak-config.configCliContainer" -}}
- name: config-cli
  image: {{ include "keycloak-config.configCliImage" . }}
  imagePullPolicy: {{ .Values.configCli.image.pullPolicy }}
  envFrom:
    - configMapRef:
        name: {{ include "keycloak-config.envConfigMapName" . }}
    {{- if and .Values.substitution.enabled .Values.substitution.existingSecret }}
    - secretRef:
        name: {{ .Values.substitution.existingSecret }}
    {{- end }}
  env:
    {{- if eq .Values.auth.mode "password" }}
    - name: KEYCLOAK_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.auth.existingSecret }}
          key: {{ .Values.auth.passwordKey }}
    {{- else }}
    - name: KEYCLOAK_CLIENTSECRET
      valueFrom:
        secretKeyRef:
          name: {{ .Values.auth.existingSecret }}
          key: {{ .Values.auth.clientSecretKey }}
    {{- end }}
    {{- with .Values.substitution.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- with .Values.configCli.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with .Values.containerSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: realm
      mountPath: /config
      readOnly: true
    - name: tmp
      mountPath: /tmp
    {{- with .Values.extraVolumeMounts }}
    {{- tpl (toYaml .) $ | nindent 4 }}
    {{- end }}
{{- end }}

{{- define "keycloak-config.pruneContainer" -}}
- name: prune
  image: {{ include "keycloak-config.keycloakImage" . }}
  imagePullPolicy: {{ .Values.keycloakImage.pullPolicy }}
  command:
    - /prune/prune.sh
  envFrom:
    - configMapRef:
        name: {{ include "keycloak-config.envConfigMapName" . }}
  env:
    {{/*
    kcadm reads its credential from these, rather than from a flag, so the
    password never lands in argv where any process can read it.
    */}}
    {{- if eq .Values.auth.mode "password" }}
    - name: KC_CLI_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.auth.existingSecret }}
          key: {{ .Values.auth.passwordKey }}
    {{- else }}
    - name: KC_CLI_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: {{ .Values.auth.existingSecret }}
          key: {{ .Values.auth.clientSecretKey }}
    {{- end }}
  securityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL
  {{- with .Values.pruneResources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: prune
      mountPath: /prune
      readOnly: true
    - name: tmp
      mountPath: /tmp
{{- end }}
