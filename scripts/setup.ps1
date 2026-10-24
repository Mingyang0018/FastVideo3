# FastVideo3 一键环境搭建（Windows PowerShell）—— 对应 TDD §3.2
#
# 默认用 **conda 环境 fastvideo3**（environment.yaml：python 3.11 + conda-forge ffmpeg）。
# 环境已存在就直接复用、不重建 —— 版本准绳是下一步的 requirements.lock.txt，重跑本脚本要幂等。
#   .\scripts\setup.ps1              conda（默认）：建/复用环境 + 装依赖 + provision + 构建前端 + 自检
#   .\scripts\setup.ps1 -Venv        改用项目内 .venv（不想用 conda，或要"交付物就是这份目录"）
#   .\scripts\setup.ps1 -Lock        另外把当前（验证过的）环境固化成 requirements.lock.txt
param(
    [switch]$Conda,  # 与默认相同，保留给老命令与习惯
    [switch]$Venv,
    [switch]$Lock
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot)

if ($Conda -and $Venv) {
    Write-Host "-Conda 与 -Venv 互斥，只给一个" -ForegroundColor Red
    exit 2
}
$UseConda = -not $Venv

if ($UseConda) {
    # 不静默降级成 venv：默认既是 conda，缺 conda 就该说清楚，而不是悄悄装到另一套环境里
    if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
        Write-Host "!! PATH 里没有 conda。装 Miniconda 后重跑，或用项目内 venv：.\scripts\setup.ps1 -Venv" -ForegroundColor Red
        exit 127
    }
    Write-Host "==> [1/6] conda 环境 fastvideo3"
    # conda env create 遇着同名现存环境会直接报错退出，所以先判在不在
    if ((& conda env list) | Where-Object { $_ -match '^\s*fastvideo3\s' }) {
        Write-Host "    环境已存在，直接复用"
    } else {
        conda env create -f environment.yaml
        if ($LASTEXITCODE -ne 0) {
            Write-Host "conda env create 失败，回退为最小环境 + pip 安装"
            conda create -n fastvideo3 python=3.11 pip -y
        }
    }
    # 非交互 PowerShell 里 `conda activate` 要先挂上 conda 自己的函数包装（未 conda init 也能用）
    & conda shell.powershell hook | Out-String | Invoke-Expression
    conda activate fastvideo3
    $Py = "python"
} else {
    Write-Host "==> [1/6] 创建项目内虚拟环境 .venv"
    $base = (Get-Command py -ErrorAction SilentlyContinue)
    if ($base) { & py -3.11 -m venv .venv } else { python -m venv .venv }
    $Py = ".venv\Scripts\python.exe"
}
# 脚本里后续都用 & $Py -m pip，不依赖 PATH 上那个 python 是哪个

Write-Host "==> [2/6] 安装 Python 依赖（含 ffmpeg 静态二进制 imageio-ffmpeg）"
& $Py -m pip install --upgrade pip
if (Test-Path requirements.lock.txt) {
    # 有锁文件就按锁装：换机器复现的是同一个版本组合，而不是"当时最新的那个"
    & $Py -m pip install -r requirements.lock.txt
} else {
    & $Py -m pip install -r requirements.txt
}

Write-Host "==> [3/6] 可选本地视觉组件（CPU 版 torch，双人同屏抠图；可跳过）"
$ans = Read-Host "安装 torch(CPU) + ultralytics + rembg + streamlit? [y/N]"
if ($ans -match '^[Yy]') {
    & $Py -m pip install torch --index-url https://download.pytorch.org/whl/cpu
    & $Py -m pip install ultralytics "rembg[cpu]" streamlit librosa soundfile
}

Write-Host "==> [4/6] 以可编辑模式安装本项目（获得 fastvideo3 命令）"
& $Py -m pip install -e .

Write-Host "==> [5/6] 配置 API KEY"
if (-not (Test-Path .env)) {
    Write-Host "尚无 .env，交给下一步从 .env.example 复制（provision 不会覆盖已有 .env）"
}

Write-Host "==> [6/6] 项目内置运行时 + 前端构建 + 环境自检"
# provision：ffmpeg 复制进 bin/（venv 里就有，离线零下载）、身份权重进 models/、缺 .env 时生成
if ($Lock) { & $Py -m fastvideo3.app.cli provision --lock } else { & $Py -m fastvideo3.app.cli provision }
if (Get-Command npm -ErrorAction SilentlyContinue) {
    Push-Location web
    npm ci
    npm run build
    Pop-Location
} else {
    Write-Host "!! 没找到 node/npm：Web 面板不会生成（API 仍可用）。装好 node 后：cd web; npm ci; npm run build" -ForegroundColor Yellow
}
& $Py -m fastvideo3.app.cli doctor
Write-Host "完成。" -ForegroundColor Green
if ($UseConda) {
    # conda 环境不在项目目录里，新开终端不会自动带上 —— 这一点和原来的 .venv 不一样
    Write-Host "  新开终端记得先激活: conda activate fastvideo3"
}
Write-Host "  面板端到端: fastvideo3 serve            → http://127.0.0.1:8000"
Write-Host "  命令行零成本演示: fastvideo3 new --topic '校园喜剧' --duration 30 --fake  然后 fastvideo3 step <run_id>（点五次补完五步）"
Write-Host "  对外上线: fastvideo3 serve --host 0.0.0.0 --port 8710"
