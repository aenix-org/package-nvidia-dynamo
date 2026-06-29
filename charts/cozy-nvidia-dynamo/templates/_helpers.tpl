{{- /*
  Shared snippets for graph-deployment.yaml. Worker components (single,
  prefill, decode) are nearly identical; rather than duplicate each
  edit across three blocks every time we add a knob, the worker spec
  fragments live here and are included from the DGD template.
*/}}

{{- /*
  cozy-nvidia-dynamo.nodeSelector — merged map of:
    serving.nodeSelector  (free-form override; wins on key conflict)
  + serving.gpuProduct    (shortcut for `nvidia.com/gpu.product=…`)
  Returns nothing when both are empty so the caller can skip emitting
  an empty `nodeSelector:` block.
*/}}
{{- define "cozy-nvidia-dynamo.nodeSelector" -}}
{{- $ns := dict -}}
{{- with .Values.serving.gpuProduct }}{{- $_ := set $ns "nvidia.com/gpu.product" . }}{{- end -}}
{{- range $k, $v := (.Values.serving.nodeSelector | default dict) }}{{- $_ := set $ns $k $v }}{{- end -}}
{{- if $ns }}
{{- toYaml $ns -}}
{{- end -}}
{{- end -}}

{{- /*
  cozy-nvidia-dynamo.workerEnvs — list of envs every worker (and the
  Frontend) needs:
    - NATS_SERVER (per-tenant, derived from cluster-domain)
    - HF_ENDPOINT (only when serving.huggingfaceEndpoint is set; lets
      tenants point HuggingFace download at an internal mirror)
*/}}
{{- define "cozy-nvidia-dynamo.workerEnvs" -}}
- name: NATS_SERVER
  value: {{ .natsServer | quote }}
{{- with .Values.serving.huggingfaceEndpoint }}
- name: HF_ENDPOINT
  value: {{ . | quote }}
{{- end }}
{{- end -}}

{{- /*
  cozy-nvidia-dynamo.workerExtraArgs — extraArgs verbatim plus, for
  vllm, `--gpu-memory-utilization=<v>` derived from the dedicated
  serving.gpuMemoryUtilization field. The derived flag is skipped
  when the user already put one in extraArgs (last-wins on the CLI,
  but emitting both is confusing).
*/}}
{{- define "cozy-nvidia-dynamo.workerExtraArgs" -}}
{{- $userHasGpuMemUtil := false -}}
{{- range .Values.serving.extraArgs -}}
  {{- if hasPrefix "--gpu-memory-utilization" . }}{{- $userHasGpuMemUtil = true }}{{- end -}}
{{- end -}}
{{- if and (eq .Values.serving.backend "vllm") (not (empty .Values.serving.gpuMemoryUtilization)) (not $userHasGpuMemUtil) }}
- {{ printf "--gpu-memory-utilization=%v" .Values.serving.gpuMemoryUtilization | quote }}
{{- end }}
{{- range .Values.serving.extraArgs }}
- {{ . | quote }}
{{- end }}
{{- end -}}

{{- /*
  cozy-nvidia-dynamo.modelCachePvcName — name DGD uses for the cache
  PVC. Defaults to `<release>-model-cache` (matches per-CR create
  mode); falls back to user-supplied `modelCache.name` when sharing
  an existing PVC across CRs (create=false).
*/}}
{{- define "cozy-nvidia-dynamo.modelCachePvcName" -}}
{{- if and (not .Values.serving.modelCache.create) .Values.serving.modelCache.name -}}
{{ .Values.serving.modelCache.name }}
{{- else -}}
{{ .Release.Name }}-model-cache
{{- end -}}
{{- end -}}

{{- /*
  cozy-nvidia-dynamo.workerExtraArgsForModel — like .workerExtraArgs but
  takes per-model extraArgs + gpuMemoryUtilization from the context
  (._modelExtraArgs / ._modelGmu). Used in multi-model mode. Same
  semantics: if the user passed --gpu-memory-utilization already, the
  derived flag is skipped.
*/}}
{{- define "cozy-nvidia-dynamo.workerExtraArgsForModel" -}}
{{- $userHasGpuMemUtil := false -}}
{{- range ._modelExtraArgs -}}
  {{- if hasPrefix "--gpu-memory-utilization" . }}{{- $userHasGpuMemUtil = true }}{{- end -}}
{{- end -}}
{{- if and (eq .Values.serving.backend "vllm") (not (empty ._modelGmu)) (not $userHasGpuMemUtil) }}
- {{ printf "--gpu-memory-utilization=%v" ._modelGmu | quote }}
{{- end }}
{{- range ._modelExtraArgs }}
- {{ . | quote }}
{{- end }}
{{- end -}}

{{- /*
  cozy-nvidia-dynamo.workerVolumeMounts — DGD `volumeMounts:` ref into
  the top-level `pvcs:` entry when modelCache is enabled. mountPoint
  covers both HuggingFace hub (`hub/`) and vLLM compile cache
  (`vllm/torch_compile_cache/`) since both live under
  /home/dynamo/.cache. Empty when modelCache.enabled is false so we
  do not emit a stray `volumeMounts:` key.
*/}}
{{- define "cozy-nvidia-dynamo.workerVolumeMounts" -}}
{{- if .Values.serving.modelCache.enabled }}
- name: {{ include "cozy-nvidia-dynamo.modelCachePvcName" . }}
  mountPoint: /home/dynamo/.cache
{{- end }}
{{- end -}}
