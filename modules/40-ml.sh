#!/usr/bin/env bash
#
# 40-ml — local AI/ML, honest about Apple Silicon. Installs only what genuinely
# runs well on M-series: uv (Python/env manager), PyTorch (MPS), the Hugging
# Face stack, Apple's MLX (+ mlx-lm) for native fine-tuning/LoRA, plus Ollama,
# llama.cpp, LM Studio and JupyterLab.
#
# CUDA-only tooling (unsloth, bitsandbytes, the CUDA paths of axolotl) is NOT
# installed — it errors on Apple Silicon. The cloud-GPU path for real large
# training/distillation is documented in docs/ml-cloud-gpu.html.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
ensure_brew_env

log_step "40 · AI / Machine Learning (Apple Silicon)"

# --- tools ------------------------------------------------------------------
brew_install uv ollama llama.cpp
brew_cask lm-studio

# Global CLIs via uv (isolated, on PATH at ~/.local/bin).
if have uv; then
  uv tool install jupyterlab      >>"$LAUNCHPAD_LOG" 2>&1 && log_ok "JupyterLab installed (run: jupyter lab)" || log_warn "JupyterLab install failed"
  uv tool install huggingface_hub >>"$LAUNCHPAD_LOG" 2>&1 && log_ok "Hugging Face CLI installed (run: hf --help)"  || log_warn "hf CLI install failed"
fi

# --- a ready-to-use Python env: PyTorch (MPS) + HF + MLX ---------------------
ml_dir="$DEVELOPER_DIR/ml-lab"
ensure_dir "$ml_dir"
if have uv; then
  py="$ml_dir/.venv/bin/python"
  if [ ! -x "$py" ]; then
    uv venv --python 3.12 "$ml_dir/.venv" >>"$LAUNCHPAD_LOG" 2>&1 || log_warn "could not create ml-lab venv"
  fi
  if [ -x "$py" ]; then
    log_info "Installing PyTorch (MPS), Hugging Face, and MLX into ml-lab/.venv (this takes a few minutes)…"
    # The default macOS torch wheel includes MPS — no CUDA index needed.
    uv pip install --python "$py" \
      torch torchvision \
      transformers datasets accelerate "huggingface_hub[cli]" \
      mlx mlx-lm \
      >>"$LAUNCHPAD_LOG" 2>&1 \
      && log_ok "ml-lab Python env ready" \
      || log_warn "some ML packages failed to install (see ${LAUNCHPAD_LOG})"
  fi
fi

# --- a tiny README so the user knows how to use the env ---------------------
if [ ! -f "$ml_dir/README.md" ]; then
  cat > "$ml_dir/README.md" <<'MD'
# ml-lab

Your local AI/ML playground (Apple Silicon).

## Activate the Python environment
```bash
cd ~/Developer/ml-lab
source .venv/bin/activate
python -c "import torch; print('MPS available:', torch.backends.mps.is_available())"
```

Installed: PyTorch (MPS), transformers, datasets, accelerate, huggingface_hub, mlx, mlx-lm.

## Run models locally
```bash
ollama run llama3.2          # chat with a model in the terminal
jupyter lab                  # notebooks in the browser
```
Or open **LM Studio** (in /Applications) for a friendly GUI.

## Fine-tuning on this Mac
Use **MLX / mlx-lm** for Apple-Silicon-native LoRA fine-tuning. For large-scale
training or distillation you need an NVIDIA (CUDA) GPU — see the cloud-GPU guide
in the Mac Launchpad docs (ml-cloud-gpu.html).
MD
  log_ok "wrote ${ml_dir}/README.md"
fi

log_note "Documented but NOT installed (CUDA-only — would error on Apple Silicon):"
log_note "  unsloth, bitsandbytes, axolotl (CUDA paths). See docs/ml-cloud-gpu.html for the cloud-GPU path."

log_ok "ML complete"
