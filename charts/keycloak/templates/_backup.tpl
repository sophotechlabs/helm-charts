{{/*
Pod spec for the pg_dump backup, shared by the CronJob and the optional
install-time seed Job so the two can never drift apart.

Takes a dict: ctx (the root context) and claim (the PVC name).
*/}}
{{- define "keycloak.backupPodSpec" -}}
{{- $ := .ctx -}}
restartPolicy: Never
{{- with $.Values.image.pullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $.Values.backup.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $.Values.backup.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $.Values.backup.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $.Values.backup.priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
containers:
  - name: pg-dump
    image: {{ printf "%s:%s" $.Values.backup.image.repository $.Values.backup.image.tag }}
    imagePullPolicy: {{ $.Values.backup.image.pullPolicy }}
    command:
      - /bin/sh
      - -ec
      - |
        for _ in $(seq {{ $.Values.backup.waitForDatabaseAttempts }})
        do
          if pg_isready -h "$PGHOST" -p "$PGPORT" -q
          then
            break
          fi
          sleep 2
        done
        pg_isready -h "$PGHOST" -p "$PGPORT" -q
        pg_dump -Fc -f "/backups/{{ include "keycloak.databaseName" $ }}-$(date +%Y%m%d-%H%M%S).dump"
        ls -1t /backups/{{ include "keycloak.databaseName" $ }}-*.dump | tail -n +{{ add1 (int $.Values.backup.retain) }} | xargs -r rm -f
    env:
      - name: PGHOST
        value: {{ include "keycloak.databaseHost" $ | quote }}
      - name: PGPORT
        value: {{ include "keycloak.databasePort" $ | quote }}
      - name: PGDATABASE
        value: {{ include "keycloak.databaseName" $ | quote }}
      - name: PGUSER
        valueFrom:
          secretKeyRef:
            name: {{ include "keycloak.databaseSecretName" $ }}
            key: {{ $.Values.database.secretKeys.usernameKey }}
      - name: PGPASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ include "keycloak.databaseSecretName" $ }}
            key: {{ $.Values.database.secretKeys.passwordKey }}
      {{- with $.Values.backup.extraEnv }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- with $.Values.backup.containerSecurityContext }}
    securityContext:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $.Values.backup.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    volumeMounts:
      - name: backups
        mountPath: /backups
      - name: tmp
        mountPath: /tmp
volumes:
  - name: tmp
    emptyDir: {}
  - name: backups
    persistentVolumeClaim:
      claimName: {{ .claim }}
{{- end }}
