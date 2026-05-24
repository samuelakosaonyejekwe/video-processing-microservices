{{/*
Expand the name of the chart.
*/}}

{{- define "postgresql.name" -}}
postgresql
{{- end }}

{{/*
Create a fully qualified app name.
*/}}

{{- define "postgresql.fullname" -}}
{{ .Release.Name }}-postgresql
{{- end }}

{{/*
PostgreSQL labels
*/}}

{{- define "postgresql.labels" -}}
app: postgresql
chart: {{ .Chart.Name }}
release: {{ .Release.Name }}
heritage: {{ .Release.Service }}
{{- end }}