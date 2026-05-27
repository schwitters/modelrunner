#!/usr/bin/env bash
#
# run-model.sh — Start llama-server with sane RTX-5090 defaults.
#
# Usage:
#   run-model.sh [model-path] [llama-server options...]
#
# Examples:
#   run-model.sh
#   run-model.sh /srv/projects/models/qwen3.6-27b-q5_k_m.gguf
#   run-model.sh --port 9090 --host 0.0.0.0
#   run-model.sh /srv/projects/models/qwen3-32b-q4_k_m.gguf --ctx-size 32768

set -euo pipefail

readonly LLAMA_SERVER="/srv/projects/llama.cpp/build-rtx-5090/bin/llama-server"
readonly LOG_DIR="/srv/projects/logs"

readonly DEFAULT_MODEL_PATH="/srv/projects/models/qwen3.6-27b-q5_k_m.gguf"

readonly DEFAULT_HOST="0.0.0.0"
readonly DEFAULT_PORT="8080"
readonly DEFAULT_N_GPU_LAYERS="999"
readonly DEFAULT_CTX_SIZE="200000"
#readonly DEFAULT_CTX_SIZE="262144"
readonly DEFAULT_PARALLEL="1"
readonly DEFAULT_FLASH_ATTN="on"
readonly DEFAULT_CACHE_TYPE_K="q8_0"
readonly DEFAULT_CACHE_TYPE_V="q8_0"
readonly DEFAULT_CACHE_RAM="16384"
readonly DEFAULT_THREADS="8"
readonly DEFAULT_THREADS_BATCH="16"

readonly DEFAULT_TEMP="0.3"
readonly DEFAULT_TOP_P="0.9"
readonly DEFAULT_MIN_P="0.05"

readonly DEFAULT_SPEC_TYPE="draft-mtp"
readonly DEFAULT_SPEC_DRAFT_N_MAX="6"
readonly DEFAULT_SPEC_DRAFT_P_MIN="0.7"

err() {
  echo "[ERROR] $*" >&2
}

log() {
  echo "[INFO]  $*" >&2
}

usage() {
  cat >&2 <<USAGE
Usage: $(basename "$0") [model-path] [llama-server options...]

Arguments:
  model-path
      Optional path to a .gguf model file.
      Default: ${DEFAULT_MODEL_PATH}

Default llama-server options:
  --model              ${DEFAULT_MODEL_PATH}
  --host               ${DEFAULT_HOST}
  --port               ${DEFAULT_PORT}
  --n-gpu-layers       ${DEFAULT_N_GPU_LAYERS}
  --ctx-size           ${DEFAULT_CTX_SIZE}
  --parallel           ${DEFAULT_PARALLEL}
  --flash-attn         ${DEFAULT_FLASH_ATTN}
  --cache-type-k       ${DEFAULT_CACHE_TYPE_K}
  --cache-type-v       ${DEFAULT_CACHE_TYPE_V}
  --jinja
  --metrics
  --spec-type          ${DEFAULT_SPEC_TYPE}
  --spec-draft-n-max   ${DEFAULT_SPEC_DRAFT_N_MAX}
  --spec-draft-p-min   ${DEFAULT_SPEC_DRAFT_P_MIN}
  --cache-ram          ${DEFAULT_CACHE_RAM}
  --threads            ${DEFAULT_THREADS}
  --threads-batch      ${DEFAULT_THREADS_BATCH}
  --temp               ${DEFAULT_TEMP}
  --top-p              ${DEFAULT_TOP_P}
  --min-p              ${DEFAULT_MIN_P}

Examples:
  $(basename "$0")
  $(basename "$0") /srv/projects/models/qwen3.6-27b-q5_k_m.gguf
  $(basename "$0") --port 9090 --host 0.0.0.0
  $(basename "$0") /srv/projects/models/qwen3-32b-q4_k_m.gguf --ctx-size 32768
USAGE
}

check_prerequisites() {
  if [[ ! -x "${LLAMA_SERVER}" ]]; then
    err "llama-server not found or not executable: ${LLAMA_SERVER}"
    exit 1
  fi

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    err "nvidia-smi not found. Is the NVIDIA driver installed?"
    exit 1
  fi
}

check_model() {
  local model_path="$1"

  if [[ ! -f "${model_path}" ]]; then
    err "Model file not found: ${model_path}"
    exit 1
  fi

  if [[ "${model_path}" != *.gguf ]]; then
    err "Expected a .gguf file, got: ${model_path}"
    exit 1
  fi
}

print_gpu_info() {
  local gpu_info
  gpu_info="$(nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null || true)"

  if [[ -n "${gpu_info}" ]]; then
    log "GPU: ${gpu_info}"
  fi
}

build_server_args() {
  local model_path="$1"
  shift

  local overrides=("$@")
  local -A overridden_options=()

  local arg
  for arg in "${overrides[@]}"; do
    if [[ "${arg}" == --* ]]; then
      overridden_options["${arg%%=*}"]=1
    fi
  done

  local args=(--model "${model_path}")

  local default_value_options=(
    --host "${DEFAULT_HOST}"
    --port "${DEFAULT_PORT}"
    --n-gpu-layers "${DEFAULT_N_GPU_LAYERS}"
    --ctx-size "${DEFAULT_CTX_SIZE}"
    --parallel "${DEFAULT_PARALLEL}"
    --flash-attn "${DEFAULT_FLASH_ATTN}"
    --cache-type-k "${DEFAULT_CACHE_TYPE_K}"
    --cache-type-v "${DEFAULT_CACHE_TYPE_V}"
    --spec-type "${DEFAULT_SPEC_TYPE}"
    --spec-draft-n-max "${DEFAULT_SPEC_DRAFT_N_MAX}"
    --spec-draft-p-min "${DEFAULT_SPEC_DRAFT_P_MIN}"
    --cache-ram "${DEFAULT_CACHE_RAM}"
    --threads "${DEFAULT_THREADS}"
    --threads-batch "${DEFAULT_THREADS_BATCH}"
    --temp "${DEFAULT_TEMP}"
    --top-p "${DEFAULT_TOP_P}"
    --min-p "${DEFAULT_MIN_P}"
  )

  local default_flag_options=(
    --jinja
    --metrics
    --kv-unified
  )

  local i
  local key
  local value

  for ((i = 0; i < ${#default_value_options[@]}; i += 2)); do
    key="${default_value_options[$i]}"
    value="${default_value_options[$((i + 1))]}"

    if [[ -z "${overridden_options[${key}]+x}" ]]; then
      args+=("${key}" "${value}")
    fi
  done

  for key in "${default_flag_options[@]}"; do
    if [[ -z "${overridden_options[${key}]+x}" ]]; then
      args+=("${key}")
    fi
  done

  args+=("${overrides[@]}")

  printf '%s\0' "${args[@]}"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local model_path="${DEFAULT_MODEL_PATH}"
  local extra_args=()

  if [[ $# -gt 0 && "${1}" != --* ]]; then
    model_path="$1"
    shift
  fi

  extra_args=("$@")

  check_prerequisites
  check_model "${model_path}"

  mkdir -p "${LOG_DIR}"

  local model_name
  model_name="$(basename "${model_path}" .gguf)"

  local log_file="${LOG_DIR}/${model_name}.log"

  local server_args=()
  while IFS= read -r -d '' arg; do
    server_args+=("${arg}")
  done < <(build_server_args "${model_path}" "${extra_args[@]}")

  log "Model: ${model_path}"
  log "Log:   ${log_file}"
  log "Args:  ${server_args[*]}"
  print_gpu_info

  exec > >(tee -a "${log_file}") 2>&1

  log "Starting llama-server..."
  exec "${LLAMA_SERVER}" "${server_args[@]}"
}

main "$@"
