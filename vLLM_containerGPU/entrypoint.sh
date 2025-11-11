#!/usr/bin/env bash
set -euo pipefail

: "${MODEL_ID:?MODEL_ID env var is required (e.g. Qwen/Qwen2.5-3B-Instruct)}"

CMD=(python3 -m vllm.entrypoints.openai.api_server --model "$MODEL_ID")

# Optional flags (only appended if set)
[[ -n "${DTYPE:-}" ]]                   && CMD+=("--dtype" "$DTYPE")
[[ -n "${GPU_MEMORY_UTILIZATION:-}" ]]  && CMD+=("--gpu-memory-utilization" "$GPU_MEMORY_UTILIZATION")
[[ -n "${MAX_MODEL_LEN:-}" ]]           && CMD+=("--max-model-len" "$MAX_MODEL_LEN")
[[ -n "${TENSOR_PARALLEL_SIZE:-}" ]]    && CMD+=("--tensor-parallel-size" "$TENSOR_PARALLEL_SIZE")
[[ -n "${MAX_NUM_SEQS:-}" ]]            && CMD+=("--max-num-seqs" "$MAX_NUM_SEQS")
[[ -n "${DOWNLOAD_DIR:-}" ]]            && CMD+=("--download-dir" "$DOWNLOAD_DIR")
[[ -n "${TRUST_REMOTE_CODE:-}" ]]       && CMD+=("--trust-remote-code" "$TRUST_REMOTE_CODE")
[[ -n "${EXTRA_ARGS:-}" ]]              && CMD+=($EXTRA_ARGS)

exec "${CMD[@]}"

