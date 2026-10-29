#!/bin/bash
# Download a model from the lineup directly into the MLX virtualenv.
#
# Usage:
#   bash scripts/download-and-import.sh                  # default Gemma 4 31B
#   bash scripts/download-and-import.sh qwen             # Qwen 3.8 27B, 8-bit
#   bash scripts/download-and-import.sh gemma12          # Gemma 4 12B
#   bash scripts/download-and-import.sh hermes           # Hermes 4 14B (text only, 4-bit)
#   bash scripts/download-and-import.sh small            # small-Mac tier for this Mac (8/16 GB)
#   bash scripts/download-and-import.sh llama            # Llama 3.3 70B (older, kept for existing users)
#   MLX_MODEL=<hf-id> bash scripts/download-and-import.sh

set -e

MLX_PYTHON="${MLX_PYTHON:-$HOME/.local/mlx-server/bin/python3}"

if [ ! -x "$MLX_PYTHON" ]; then
  echo "ERROR: MLX virtualenv not found at $MLX_PYTHON"
  echo "Run setup.sh first."
  exit 1
fi

case "${1:-}" in
  qwen|qwen38|27b)
    # https://huggingface.co/lmstudio-community/Qwen3.8-27B-MLX-8bit
    MODEL="${MLX_MODEL:-lmstudio-community/Qwen3.8-27B-MLX-8bit}"
    LABEL="Qwen 3.8 27B, 8-bit (~29 GB, 96 GB Macs)"
    ;;
  gemma12|12b)
    MODEL="${MLX_MODEL:-divinetribe/gemma-4-12B-it-abliterated-4bit-mlx-text}"
    LABEL="Gemma 4 12B Abliterated, 4-bit (~11 GB)"
    ;;
  hermes|14b)
    MODEL="${MLX_MODEL:-divinetribe/Hermes-4-14B-abliterated-4bit-mlx}"
    LABEL="Hermes 4 14B Abliterated, 4-bit (~8 GB, 16 GB Macs)"
    ;;
  small|tier|small-mac)
    # The small-Mac tier for this Mac (scripts/mac-tier.sh). Vision models, so
    # they go to a flat folder with every file (processor configs included).
    source "$(cd "$(dirname "$0")" && pwd)/mac-tier.sh"
    if [ "$CCL_TIER" = "none" ]; then
      echo "This Mac has 32 GB or more; no small-Mac tier. Force one: CCL_TIER=16gb $0 small"
      exit 1
    fi
    echo "=== Downloading $CCL_MODEL_LABEL ($CCL_TIER tier) ==="
    "$MLX_PYTHON" -c "import mlx_vlm" 2>/dev/null || "$MLX_PYTHON" -m pip install --quiet mlx-vlm
    "$MLX_PYTHON" - <<PY
from huggingface_hub import snapshot_download
snapshot_download("$CCL_MODEL_ID", local_dir="$CCL_MODEL_DIR")
print("Done.")
PY
    echo ""
    echo "=== DONE! Double-click launchers/Small Mac.command"
    exit 0
    ;;
  llama|llama70|70b)
    # Older model, no current measurements. Kept so existing setups keep working.
    MODEL="${MLX_MODEL:-divinetribe/Llama-3.3-70B-Instruct-abliterated-8bit-mlx}"
    LABEL="Llama 3.3 70B Abliterated, 8-bit (older, ~75 GB)"
    ;;
  gemma|gemma31|31b|"")
    # Our own abliterated MLX upload:
    #   https://huggingface.co/divinetribe/gemma-4-31b-it-abliterated-4bit-mlx
    MODEL="${MLX_MODEL:-divinetribe/gemma-4-31b-it-abliterated-4bit-mlx}"
    LABEL="Gemma 4 31B Abliterated, 4-bit (~18 GB)"
    ;;
  *)
    MODEL="$1"
    LABEL="$1"
    ;;
esac

echo "=== Downloading $LABEL ==="
echo "    HuggingFace ID: $MODEL"
echo ""

"$MLX_PYTHON" - <<PY
from mlx_lm.utils import load
print("Downloading + loading $MODEL ...")
load("$MODEL")
print("Done.")
PY

echo ""
echo "=== DONE! Start the server with:"
echo "    MLX_MODEL=$MODEL bash scripts/start-mlx-server.sh"
