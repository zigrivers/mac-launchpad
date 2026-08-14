# 40-ml — local AI/ML. Windows twin of modules/40-ml.sh.
# Installs uv (Python/env manager), PyTorch (CUDA when an NVIDIA GPU is
# present, CPU wheels otherwise), the Hugging Face stack, plus Ollama,
# LM Studio and JupyterLab.
#
# Skipped vs the macOS module:
#   * llama.cpp — no winget package; Ollama + LM Studio cover local models.
#   * mlx / mlx-lm — Apple-Silicon-only, would error on Windows.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\common.ps1')

Log-Step '40 · AI / Machine Learning'

# --- tools --------------------------------------------------------------------
Winget-Install @('astral-sh.uv', 'Ollama.Ollama', 'ElementLabs.LMStudio')
Refresh-SessionPath

# Global CLIs via uv (isolated, on PATH at ~\.local\bin).
if (Have uv) {
    uv tool install jupyterlab >> $env:LAUNCHPAD_LOG 2>&1
    if ($LASTEXITCODE -eq 0) { Log-Ok 'JupyterLab installed (run: jupyter-lab)' }
    else { Log-Warn 'JupyterLab install failed' }
    uv tool install huggingface_hub >> $env:LAUNCHPAD_LOG 2>&1
    if ($LASTEXITCODE -eq 0) { Log-Ok 'Hugging Face CLI installed (run: hf --help)' }
    else { Log-Warn 'hf CLI install failed' }
}

# --- a ready-to-use Python env: PyTorch + HF ----------------------------------
$mlDir = Join-Path $script:DEVELOPER_DIR 'ml-lab'
Ensure-Dir $mlDir
$hasGpu = Have nvidia-smi
if (Have uv) {
    $py = Join-Path $mlDir '.venv\Scripts\python.exe'
    if (-not (Test-Path $py)) {
        uv venv --python 3.12 (Join-Path $mlDir '.venv') >> $env:LAUNCHPAD_LOG 2>&1
        if ($LASTEXITCODE -ne 0) { Log-Warn 'could not create ml-lab venv' }
    }
    if (Test-Path $py) {
        if ($hasGpu) {
            # NVIDIA GPU detected — CUDA wheels from the official PyTorch index
            # (verified 2026-08-14 at pytorch.org/get-started/locally).
            Log-Info 'Installing PyTorch (CUDA) and Hugging Face into ml-lab\.venv (this takes a few minutes)...'
            uv pip install --python $py --index-url https://download.pytorch.org/whl/cu126 torch torchvision >> $env:LAUNCHPAD_LOG 2>&1
        } else {
            Log-Info 'Installing PyTorch (CPU) and Hugging Face into ml-lab\.venv (this takes a few minutes)...'
            uv pip install --python $py torch torchvision >> $env:LAUNCHPAD_LOG 2>&1
        }
        $torchOk = ($LASTEXITCODE -eq 0)
        uv pip install --python $py transformers datasets accelerate 'huggingface_hub[cli]' >> $env:LAUNCHPAD_LOG 2>&1
        if ($torchOk -and $LASTEXITCODE -eq 0) { Log-Ok 'ml-lab Python env ready' }
        else { Log-Warn "some ML packages failed to install (see $env:LAUNCHPAD_LOG)" }
        if (-not $hasGpu) {
            Log-Note 'No NVIDIA GPU detected - installed CPU wheels. Got a CUDA GPU later? Re-install with:'
            Log-Note '  uv pip install --python ml-lab\.venv\Scripts\python.exe --index-url https://download.pytorch.org/whl/cu126 torch torchvision'
        }
    }
}

# --- a tiny README so the user knows how to use the env -----------------------
$readme = Join-Path $mlDir 'README.md'
if (-not (Test-Path $readme)) {
    @'
# ml-lab

Your local AI/ML playground (Windows).

## Activate the Python environment
```powershell
cd ~\Developer\ml-lab
.venv\Scripts\activate
python -c "import torch; print('CUDA available:', torch.cuda.is_available())"
```

Installed: PyTorch, transformers, datasets, accelerate, huggingface_hub.

## Run models locally
```powershell
ollama run llama3.2          # chat with a model in the terminal
jupyter-lab                  # notebooks in the browser
```
Or open **LM Studio** (Start menu) for a friendly GUI.

## GPU (CUDA)
With an NVIDIA GPU, setup installed CUDA wheels automatically. On a machine
without one you got CPU wheels — switch later with:
```powershell
uv pip install --python .venv\Scripts\python.exe --index-url https://download.pytorch.org/whl/cu126 torch torchvision
```
For large-scale training or distillation see the cloud-GPU guide in the
Mac Launchpad docs (ml-cloud-gpu.html).
'@ | Set-Content -Path $readme -Encoding UTF8
    Log-Ok "wrote $readme"
}

Log-Ok 'ML complete'
