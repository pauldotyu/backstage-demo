{{- define "backstage.name" -}}
{{- default "backstage" .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "backstage.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "backstage" .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "backstage.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "backstage.labels" -}}
helm.sh/chart: {{ include "backstage.chart" . }}
{{ include "backstage.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "backstage.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backstage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: backstage
{{- end }}

{{- define "backstage.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "backstage.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "backstage.image" -}}
{{- $repo := .Values.image.repository }}
{{- if .Values.image.registry }}{{ $repo = printf "%s/%s" .Values.image.registry $repo }}{{ end }}
{{- if .Values.image.digest }}
{{- printf "%s@%s" $repo .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" $repo (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}
{{- end }}

{{/* Public URL of Backstage. */}}
{{- define "backstage.baseUrl" -}}
{{- if .Values.baseUrl }}
{{- .Values.baseUrl | trimSuffix "/" }}
{{- else if .Values.gateway.enabled }}
{{- printf "https://%s" (required "gateway.hostname is required when gateway.enabled is true (for example backstage.<id>.<region>.aksapp.io)" .Values.gateway.hostname) }}
{{- else }}
{{- "http://localhost:7007" }}
{{- end }}
{{- end }}

{{/* Final appConfig: chart-computed URLs, overridden by .Values.appConfig. */}}
{{- define "backstage.appConfig" -}}
{{- $url := include "backstage.baseUrl" . }}
{{- $computed := dict "app" (dict "baseUrl" $url) "backend" (dict "baseUrl" $url "cors" (dict "origin" $url)) }}
{{- toYaml (mustMergeOverwrite $computed (deepCopy (.Values.appConfig | default dict))) }}
{{- end }}

{{- define "backstage.tlsSecretName" -}}
{{- default (printf "%s-tls" (include "backstage.fullname" .)) .Values.gateway.tls.secretName }}
{{- end }}

{{/* PostgreSQL */}}
{{/*
Istio copies Gateway labels onto the gateway pods it creates, so the Gateway
must not carry the Backstage selector labels or the Backstage Service would
select the gateway pods too.
*/}}
{{- define "backstage.gateway.labels" -}}
helm.sh/chart: {{ include "backstage.chart" . }}
app.kubernetes.io/name: {{ include "backstage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: gateway
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "backstage.postgresql.fullname" -}}
{{- printf "%s-postgresql" (include "backstage.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "backstage.postgresql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backstage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: postgresql
{{- end }}

{{- define "backstage.postgresql.labels" -}}
helm.sh/chart: {{ include "backstage.chart" . }}
{{ include "backstage.postgresql.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.postgresql.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "backstage.postgresql.secretName" -}}
{{- default (include "backstage.postgresql.fullname" .) .Values.postgresql.auth.existingSecret }}
{{- end }}

{{/* Database environment variables consumed by app-config.production.yaml. */}}
{{- define "backstage.databaseEnv" -}}
{{- if .Values.postgresql.enabled }}
- name: POSTGRES_HOST
  value: {{ include "backstage.postgresql.fullname" . | quote }}
- name: POSTGRES_PORT
  value: "5432"
- name: POSTGRES_USER
  value: {{ .Values.postgresql.auth.username | quote }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "backstage.postgresql.secretName" . }}
      key: {{ .Values.postgresql.auth.secretKey }}
{{- else }}
{{- $secret := .Values.externalDatabase.existingSecret | default .Values.existingSecret }}
- name: POSTGRES_HOST
  value: {{ required "externalDatabase.host is required when postgresql.enabled is false" .Values.externalDatabase.host | quote }}
- name: POSTGRES_PORT
  value: {{ .Values.externalDatabase.port | quote }}
- name: POSTGRES_USER
  value: {{ required "externalDatabase.user is required when postgresql.enabled is false" .Values.externalDatabase.user | quote }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ required "externalDatabase.existingSecret or existingSecret is required when postgresql.enabled is false" $secret }}
      key: {{ .Values.externalDatabase.existingSecretPasswordKey }}
{{- with .Values.externalDatabase.sslMode }}
- name: PGSSLMODE
  value: {{ . | quote }}
{{- end }}
{{- end }}
{{- end }}
