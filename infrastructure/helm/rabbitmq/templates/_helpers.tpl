{{/*
Expand the name of the chart.
*/}}

{{- define "rabbitmq.name" -}}
rabbitmq
{{- end }}

{{/*
Create a fully qualified app name.
*/}}

{{- define "rabbitmq.fullname" -}}
{{ .Release.Name }}-rabbitmq
{{- end }}

{{/*
RabbitMQ labels
*/}}

{{- define "rabbitmq.labels" -}}
app: rabbitmq
chart: {{ .Chart.Name }}
release: {{ .Release.Name }}
heritage: {{ .Release.Service }}
{{- end }}