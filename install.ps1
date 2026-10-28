# Claude Code Local - Windows installer (llama.cpp backend, vision model).
#
#   irm https://raw.githubusercontent.com/nicedreamzapp/claude-code-local/main/install.ps1 | iex
#
# Clones the repo to %USERPROFILE%\claude-code-local, then detects your hardware,
# downloads a pinned llama.cpp build plus the best vision model that fits, and
# writes a launcher. Needs git and Python 3 on PATH. No Ollama, no LM Studio.

$ErrorActionPreference = "Stop"

$RepoUrl    = "https://github.com/nicedreamzapp/claude-code-local"
$InstallDir = if ($env:CCL_DIR) { $env:CCL_DIR } else { Join-Path $env:USERPROFILE "claude-code-local" }

Write-Host ""
Write-Host "=============================================="
Write-Host "    Claude Code Local - Windows installer"
Write-Host "=============================================="
Write-Host ""

function Need($cmd, $hint) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Host "x $cmd not found. $hint"
    exit 1
  }
}
Need "git" "Install Git for Windows from https://git-scm.com/download/win"
Need "python" "Install Python 3 from https://www.python.org/downloads/ (check 'Add to PATH')"

Write-Host ("  Windows: " + (Get-CimInstance Win32_Processor).Name)
Write-Host ""

if (Test-Path (Join-Path $InstallDir ".git")) {
  Write-Host "-> Updating existing install at $InstallDir"
  git -C $InstallDir pull --ff-only
} elseif (Test-Path $InstallDir) {
  Write-Host "x $InstallDir exists and is not a git checkout. Move it aside or set CCL_DIR."
  exit 1
} else {
  Write-Host "-> Cloning into $InstallDir"
  git clone --depth 1 $RepoUrl $InstallDir
}

$ccl = Join-Path $InstallDir "portable\ccl.py"

Write-Host ""
Write-Host "Detecting hardware and picking a model..."
python -I $ccl detect

Write-Host ""
Write-Host "Downloading llama.cpp + model (one time, can be large)..."
python -I $ccl install

# Launcher: a small .cmd on the Desktop and in the install dir.
$launcher = Join-Path $InstallDir "claude-local.cmd"
"@echo off`r`npython -I `"$ccl`" run %*`r`n" | Set-Content -Encoding ASCII $launcher
$desktop = [Environment]::GetFolderPath("Desktop")
Copy-Item $launcher (Join-Path $desktop "Claude Local.cmd") -Force

Write-Host ""
Write-Host "=============================================="
Write-Host "    Setup complete!"
Write-Host "    Double-click 'Claude Local' on your Desktop,"
Write-Host "    or run:  $launcher"
Write-Host "=============================================="
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host ""
  Write-Host "Note: Claude Code CLI not found. Install it, then launch again."
}
