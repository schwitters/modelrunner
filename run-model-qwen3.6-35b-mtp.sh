#!/usr/bin/env bash
#
# run-model.sh — Start llama-server with a given model and optional overrides.
#
# Usage:
#   run-model.sh <model-path> [llama-server options...]
#
# Examples:
#   run-model.sh /srv/projects/models/qwen3-32b-q4_k_m.gguf
#   run-model.sh /srv/projects/models/qwen3-32b-q4_k_m.gguf --port 9090 --parallel 4
#   run-model.sh /srv/projects/models/qwen2.5-coder-7b-instruct-q4_k_m.gguf --ctx-size 32768

set -euo pipefail

readonly LLAMA_SERVER="/srv/projects/llama.cpp/build-rtx-5090/bin/llama-server"
#/srv/projects/llama.cpp/build/bin/llama-server"
readonly LOG_DIR="/srv/projects/logs"

# Defaults (can be overridden via arguments)
readonly DEFAULT_N_GPU_LAYERS=999
readonly DEFAULT_CTX_SIZE=200000
readonly DEFAULT_PARALLEL=1
readonly DEFAULT_CACHE_TYPE_K="q8_0"
readonly DEFAULT_CACHE_TYPE_V="q8_0"
readonly DEFAULT_HOST="0.0.0.0"
readonly DEFAULT_PORT=8080
# MTP enabled model
readonly DEFAULT_MODEL_PATH="/srv/projects/models/qwen3.6-35b-a3b-ud-q5_k_m.gguf"
#qwen3.6-35b-a3b-q5_k_m.gguf"

# -----------------------------------------------------------------------------

err() {
  echo "[ERROR] $*" >&2
}

log() {
  echo "[INFO]  $*" >&2
}

usage() {
  cat >&2 << USAGE

Usage: $(basename "$0") <model-path> [llama-server options...]

Arguments:
  model-path              Path to the .gguf model file (required)

Default server options (override by passing the flag explicitly):
  --n-gpu-layers ${DEFAULT_N_GPU_LAYERS}
  --ctx-size     ${DEFAULT_CTX_SIZE}
  --parallel     ${DEFAULT_PARALLEL}
  --cache-type-k ${DEFAULT_CACHE_TYPE_K}
  --cache-type-v ${DEFAULT_CACHE_TYPE_V}
  --host         ${DEFAULT_HOST}
  --port         ${DEFAULT_PORT}
  --flash-attn         on

Examples:
  $(basename "$0") /srv/projects/models/qwen3-32b-q4_k_m.gguf
  $(basename "$0") /srv/projects/models/qwen3-32b-q4_k_m.gguf --port 9090 --parallel 4
  $(basename "$0") /srv/projects/models/qwen2.5-coder-7b-instruct-q4_k_m.gguf --ctx-size 32768

USAGE
  exit 1
}

check_prerequisites() {
  if [[ ! -x "${LLAMA_SERVER}" ]]; then
    err "llama-server not found or not executable: ${LLAMA_SERVER}"
    err "Build llama.cpp first: see /srv/projects/notes/server_setup.md"
    exit 1
  fi

  if ! command -v nvidia-smi &> /dev/null; then
    err "nvidia-smi not found — is the NVIDIA driver installed?"
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

  # Start with defaults
  local -A defaults=(
    [--n-gpu-layers]="${DEFAULT_N_GPU_LAYERS}"
    [--ctx-size]="${DEFAULT_CTX_SIZE}"
    [--parallel]="${DEFAULT_PARALLEL}"
    [--cache-type-k]="${DEFAULT_CACHE_TYPE_K}"
    [--cache-type-v]="${DEFAULT_CACHE_TYPE_V}"
    [--host]="${DEFAULT_HOST}"
    [--port]="${DEFAULT_PORT}"
    [--flash-attn]="on"
    [--jinja]=""
    [--temp]="0.2"
    [--top-p]="0.9"
    [--min-p]="0.05"
    [--spec-type]="draft-mtp"
    [--spec-draft-p-min]="0.75"
    [--spec-draft-n-max]="6"
    [--kv-unified]=""
    [--metrics]=""
    [--cache-ram]="16384"
    [--threads]="8"
    [--threads-batch]="16"
  )

  # Apply overrides: remove any default key that appears in the overrides
  local i
  for (( i=0; i<${#overrides[@]}; i++ )); do
    local key="${overrides[$i]}"
    if [[ "${key}" == --* ]]; then
      unset "defaults[${key}]"
    fi
  done

  # Build final args: defaults first, then overrides
  local args=(--model "${model_path}")
  for key in "${!defaults[@]}"; do
    args+=("${key}" "${defaults[${key}]}")
  done
  args+=("${overrides[@]}")

  echo "${args[@]}"
}

main() {
  #if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  #  usage
  #fi

  local model_path="$DEFAULT_MODEL_PATH"
  local extra_args=""

  check_prerequisites
  check_model "${model_path}"

  mkdir -p "${LOG_DIR}"

  local model_name
  model_name="$(basename "${model_path}" .gguf)"
  local log_file="${LOG_DIR}/${model_name}.log"

  local server_args
  read -ra server_args <<< "$(build_server_args "${model_path}" "${extra_args[@]}")"

  log "Model:  ${model_path}"
  log "Log:    ${log_file}"
  log "Args:   ${server_args[*]}"
  print_gpu_info

  log "Starting llama-server..."
  exec "${LLAMA_SERVER}" "${server_args[@]}" 2>&1 | tee "${log_file}"
}

main "$@"
