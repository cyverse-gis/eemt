{{/*
Expand the name of the chart.
*/}}
{{- define "eemt.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "eemt.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "eemt.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "eemt.labels" -}}
helm.sh/chart: {{ include "eemt.chart" . }}
{{ include "eemt.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "eemt.selectorLabels" -}}
app.kubernetes.io/name: {{ include "eemt.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Web interface labels
*/}}
{{- define "eemt.webInterface.labels" -}}
{{ include "eemt.labels" . }}
app.kubernetes.io/component: web-interface
{{- end }}

{{/*
Web interface selector labels
*/}}
{{- define "eemt.webInterface.selectorLabels" -}}
{{ include "eemt.selectorLabels" . }}
app.kubernetes.io/component: web-interface
{{- end }}

{{/*
Worker labels
*/}}
{{- define "eemt.worker.labels" -}}
{{ include "eemt.labels" . }}
app.kubernetes.io/component: worker
{{- end }}

{{/*
Worker selector labels
*/}}
{{- define "eemt.worker.selectorLabels" -}}
{{ include "eemt.selectorLabels" . }}
app.kubernetes.io/component: worker
{{- end }}

{{/*
Cleanup labels
*/}}
{{- define "eemt.cleanup.labels" -}}
{{ include "eemt.labels" . }}
app.kubernetes.io/component: cleanup
{{- end }}

{{/*
Cleanup selector labels
*/}}
{{- define "eemt.cleanup.selectorLabels" -}}
{{ include "eemt.selectorLabels" . }}
app.kubernetes.io/component: cleanup
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "eemt.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "eemt.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the image reference for web interface
*/}}
{{- define "eemt.webInterface.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" -}}
{{- $repository := .Values.image.webInterface.repository -}}
{{- $tag := .Values.image.webInterface.tag | default .Chart.AppVersion -}}
{{- if $registry -}}
{{ printf "%s/%s:%s" $registry $repository $tag }}
{{- else -}}
{{ printf "%s:%s" $repository $tag }}
{{- end -}}
{{- end }}

{{/*
Create the image reference for worker
*/}}
{{- define "eemt.worker.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" -}}
{{- $repository := .Values.image.worker.repository -}}
{{- $tag := .Values.image.worker.tag | default .Chart.AppVersion -}}
{{- if $registry -}}
{{ printf "%s/%s:%s" $registry $repository $tag }}
{{- else -}}
{{ printf "%s:%s" $repository $tag }}
{{- end -}}
{{- end }}

{{/*
Create environment variables for EEMT configuration
*/}}
{{- define "eemt.envVars" -}}
- name: EEMT_MODE
  value: {{ .Values.global.eemt.mode | quote }}
- name: EEMT_CLEANUP_ENABLED
  value: {{ .Values.global.eemt.cleanup.enabled | quote }}
- name: EEMT_SUCCESS_RETENTION_DAYS
  value: {{ .Values.global.eemt.cleanup.successRetentionDays | quote }}
- name: EEMT_FAILED_RETENTION_HOURS
  value: {{ .Values.global.eemt.cleanup.failedRetentionHours | quote }}
- name: EEMT_NUM_THREADS
  value: {{ .Values.config.eemt.numThreads | quote }}
- name: EEMT_LINKE_VALUE
  value: {{ .Values.config.eemt.linkeValue | quote }}
- name: EEMT_ALBEDO_VALUE
  value: {{ .Values.config.eemt.albedoValue | quote }}
- name: GRASS_GISBASE
  value: {{ .Values.config.grass.gisbase | quote }}
- name: WORK_QUEUE_PORT
  value: {{ .Values.config.cctools.workQueuePort | quote }}
- name: WORK_QUEUE_PROJECT
  value: {{ .Values.config.cctools.projectName | quote }}
- name: PYTHONPATH
  value: "/app:/opt/eemt"
{{- end }}

{{/*
Create volume mounts for persistent storage
*/}}
{{- define "eemt.volumeMounts" -}}
{{- if .Values.persistence.data.enabled }}
- name: data-storage
  mountPath: /app/data
{{- end }}
{{- if .Values.persistence.database.enabled }}
- name: database-storage
  mountPath: /app/database
{{- end }}
{{- if .Values.persistence.cache.enabled }}
- name: cache-storage
  mountPath: /app/cache
{{- end }}
{{- if .Values.persistence.logs.enabled }}
- name: logs-storage
  mountPath: /app/logs
{{- end }}
{{- end }}

{{/*
Create volumes for persistent storage
*/}}
{{- define "eemt.volumes" -}}
{{- if .Values.persistence.data.enabled }}
- name: data-storage
  persistentVolumeClaim:
    claimName: {{ include "eemt.fullname" . }}-data
{{- end }}
{{- if .Values.persistence.database.enabled }}
- name: database-storage
  persistentVolumeClaim:
    claimName: {{ include "eemt.fullname" . }}-database
{{- end }}
{{- if .Values.persistence.cache.enabled }}
- name: cache-storage
  persistentVolumeClaim:
    claimName: {{ include "eemt.fullname" . }}-cache
{{- end }}
{{- if .Values.persistence.logs.enabled }}
- name: logs-storage
  persistentVolumeClaim:
    claimName: {{ include "eemt.fullname" . }}-logs
{{- end }}
{{- end }}

{{/*
Resource strategy configuration
*/}}
{{- define "eemt.resources" -}}
{{- $component := . -}}
{{- $root := .root -}}
{{- if eq ($root.Values.global.resourceStrategy | default "balanced") "minimal" -}}
requests:
  cpu: 100m
  memory: 256Mi
limits:
  cpu: 500m
  memory: 1Gi
{{- else if eq ($root.Values.global.resourceStrategy | default "balanced") "performance" -}}
requests:
  cpu: 2000m
  memory: 4Gi
limits:
  cpu: 8000m
  memory: 16Gi
{{- else -}}
{{- toYaml $component.resources -}}
{{- end -}}
{{- end -}}