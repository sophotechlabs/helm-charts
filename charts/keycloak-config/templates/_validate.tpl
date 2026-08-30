{{/*
Guards on the realm definition, checked at render time so a bad file fails the
install rather than a job three minutes later. Every fail message is one line:
helm-unittest keeps only the first line of a render error.
*/}}
{{- define "keycloak-config.validate" -}}
{{- if not .Values.keycloak.url }}
{{- fail "keycloak.url is required; point it at the in-cluster Service over http, because the admin client does not follow a 308 redirect" }}
{{- end }}
{{- if not .Values.auth.existingSecret }}
{{- fail "auth.existingSecret is required; without it the admin CLI prompts for a password on a terminal the job does not have and hangs" }}
{{- end }}
{{- if and (eq .Values.auth.mode "client") (not .Values.auth.clientId) }}
{{- fail "auth.clientId is required when auth.mode is client" }}
{{- end }}
{{- if not .Values.realm.spec }}
{{- fail "realm.spec is empty; supply it by path with --set-file realm.spec=./realm.yaml, or under Flux with a valuesFrom entry using targetPath: realm.spec" }}
{{- end }}
{{- $realm := fromYaml (include "keycloak-config.realmText" .) }}
{{- if $realm.Error }}
{{- fail (printf "realm.spec is not parseable as YAML: %s" ($realm.Error | replace "\n" " ")) }}
{{- end }}
{{- if not $realm.realm }}
{{- fail "realm.spec has no top-level realm: key, so there is nothing to say which realm it configures" }}
{{- end }}
{{- include "keycloak-config.validateCredentials" . }}
{{- if and .Values.substitution.enabled (not .Values.substitution.existingSecret) }}
{{- if regexMatch "\\$\\(env:" (include "keycloak-config.realmText" .) }}
{{- fail "realm.spec uses $(env:…) placeholders but substitution.existingSecret is not set, so they would resolve to nothing" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Every password credential has to be create-only.

config-cli compares the user it is about to write against the one the admin API
returns, and the returned user never carries credentials — so a user with a
password in the file always compares as changed, and Keycloak then re-hashes
the password on every run. On a schedule that silently reverts any password the
person chose themselves. A userLabel of "initial" is the documented, code-
enforced way to make the credential apply only at creation.
*/}}
{{- define "keycloak-config.validateCredentials" -}}
{{- $realm := fromYaml (include "keycloak-config.realmText" .) }}
{{- range $realm.users }}
{{- $username := .username | default "<unnamed>" }}
{{- range .credentials }}
{{- if eq (.type | default "password") "password" }}
{{- if ne (.userLabel | default "") "initial" }}
{{- fail (printf "password credential for user %s must carry userLabel: initial, otherwise every reconcile re-hashes it and reverts a password the user chose themselves" $username) }}
{{- end }}
{{- if .temporary }}
{{- fail (printf "password credential for user %s sets temporary: true, which re-adds the UPDATE_PASSWORD required action on every run and prompts a user who already changed it" $username) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
