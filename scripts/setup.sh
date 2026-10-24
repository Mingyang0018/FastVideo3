#!/usr/bin/env bash
# FastVideo3 一键环境搭建（Linux / macOS）—— 对应 TDD §3.2
#
# 默认用 **conda 环境 fastvideo3**（environment.yaml：python 3.11 + conda-forge ffmpeg）。
# 环境已存在就直接复用，不重建 —— 真正的版本准绳是下一步的 requirements.lock.txt。
#   ./scripts/setup.sh              conda（默认）
#   ./scripts/setup.sh --venv       改用项目内 .venv（没装 conda 的机器，或想要"交付物就是这份目录"）
#   ./scripts/setup.sh --lock       另外把当前（验证过的）环境固化成 requirements.lock.txt
set -e
cd "$(dirname "$0")/.."

USE_CONDA=1
LOCK=0
for arg in "$@"; do
    case "$arg" in
        --conda) USE_CONDA=1 ;;  # 与默认相同，保留给老命令与习惯
        --venv) USE_CONDA=0 ;;
        --lock) LOCK=1 ;;  # 把当前（验证过的）环境固化成 requirements.lock.txt
        *) echo "未知参数 $arg（可用：--conda --venv --lock）" >&2; exit 2 ;;
    esac
done

if [ "$USE_CONDA" = "1" ]; then
    # 不静默降级成 venv：默认既是 conda，缺 conda 就该说清楚，而不是悄悄装到另一套环境里
    if ! command -v conda >/dev/null 2>&1; then
        echo "!! PATH 里没有 conda。装 Miniconda 后重跑，或用项目内 venv：./scripts/setup.sh --venv" >&2
        exit 127
    fi
    echo "==> [1/6] conda 环境 fastvideo3"
    # conda env create 遇着同名现存环境会直接报错退出，所以先判在不在（重跑本脚本要能幂等）
    if conda env list | awk '{print $1}' | grep -qx fastvideo3; then
        echo "    环境已存在，直接复用"
    else
        conda env create -f environment.yaml || {
            echo "conda env create 失败，回退为最小环境 + pip 安装"
            conda create -n fastvideo3 python=3.11 pip -y
        }
    fi
    eval "$(conda shell.bash hook)"
    conda activate fastvideo3
    PY=python
else
    echo "==> [1/6] 创建项目内虚拟环境 .venv（Python $(python3 -V 2>/dev/null || echo 需自备 3.11+)）"
    python3 -m venv .venv
    PY=".venv/bin/python"
fi

echo "==> [2/6] 安装 Python 依赖（含 ffmpeg 静态二进制 imageio-ffmpeg）"
# 有锁文件就按锁装：换机器复现的是同一个版本组合，而不是"当时最新的那个"
if [ -f requirements.lock.txt ]; then
    "$PY" -m pip install --upgrade pip
    "$PY" -m pip install -r requirements.lock.txt
else
    "$PY" -m pip install --upgrade pip
    "$PY" -m pip install -r requirements.txt
fi

echo "==> [3/6] 可选本地视觉组件（CPU 版 torch，双人同屏抠图；可跳过）"
read -r -p "安装 torch(CPU) + ultralytics + rembg + streamlit? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    "$PY" -m pip install torch --index-url https://download.pytorch.org/whl/cpu
    "$PY" -m pip install ultralytics "rembg[cpu]" streamlit librosa soundfile || true
fi

echo "==> [4/6] 以可编辑模式安装本项目（获得 fastvideo3 命令）"
"$PY" -m pip install -e .

echo "==> [5/6] 配置 API KEY"
if [ ! -f .env ]; then
    "$PY" -m fastvideo3.app.cli provision   # 缺 .env 时从模板复制，并收 ffmpeg/权重进项目
    echo "请编辑 .env 填入 DASHSCOPE_API_KEY（与可选的 FAL_KEY）"
fi

echo "==> [6/6] 项目内置运行时 + 前端构建 + 环境自检"
if [ "$LOCK" = "1" ]; then
    "$PY" -m fastvideo3.app.cli provision --lock
else
    "$PY" -m fastvideo3.app.cli provision
fi
if command -v npm >/dev/null 2>&1; then
    (cd web && npm ci && npm run build)
else
    echo "!! 没找到 node/npm：Web 面板不会生成（API 仍可用）。装好 node 后：cd web && npm ci && npm run build"
fi
"$PY" -m fastvideo3.app.cli doctor
echo "✔ 完成。"
# conda 环境不在项目目录里，新开终端不会自动带上 —— 这一点和原来的 .venv 不一样，写在收尾提示里
if [ "$USE_CONDA" = "1" ]; then
    echo "  新开终端记得先激活: conda activate fastvideo3"
fi
echo "  面板端到端: fastvideo3 serve            → http://127.0.0.1:8000"
echo "  命令行零成本演示: fastvideo3 new --topic '校园喜剧' --duration 30 --fake  然后 fastvideo3 step <run_id>（点五次补完五步）"
echo "  对外上线: fastvideo3 serve --host 0.0.0.0 --port 8710"
