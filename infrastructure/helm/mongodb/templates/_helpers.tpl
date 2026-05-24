{{/*
Expand the name of the chart.
*/}}

{{- define "mongodb.name" -}}
mongodb
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}

{{- define "mongodb.fullname" -}}
{{ .Release.Name }}-mongodb
{{- end }}