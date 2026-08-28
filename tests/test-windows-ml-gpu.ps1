param([string]$Python = '')

$ErrorActionPreference = 'Stop'

$developerDir = if ($env:DEVELOPER_DIR) { $env:DEVELOPER_DIR } else { Join-Path $HOME 'Developer' }
$python = if ($Python) { $Python } else { Join-Path $developerDir 'ml-lab\.venv\Scripts\python.exe' }
if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP: no NVIDIA GPU detected.'
    exit 0
}
if (-not (Test-Path -LiteralPath $python)) {
    Write-Host 'SKIP: ml-lab environment is not installed.'
    exit 0
}

$program = @'
import torch

assert torch.cuda.is_available(), "PyTorch cannot access CUDA"
x = torch.arange(16, dtype=torch.float32, device="cuda").reshape(4, 4)
y = x @ x
torch.cuda.synchronize()
assert y.device.type == "cuda"
assert y.shape == (4, 4)
print(f"PASS: {torch.__version__} computed on {torch.cuda.get_device_name(0)}")
'@

& $python -c $program
if ($LASTEXITCODE -ne 0) {
    throw 'The ml-lab PyTorch build could not execute a CUDA kernel.'
}
