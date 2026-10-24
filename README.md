# FastVideo3 🎬

输入一个主题，产出一部带对白、带口型、带转场的 AI 短剧 —— **全程走 API，不需要 GPU**。

- **五步一条路径**：`剧本 → 角色图 → 场景图 → 场景视频 → 成片`。点一次补一步，每步之间人都能介入。
- **多模态**：一次 wan3.0 调用吃「角色立绘 + 场景图 + 音色样本 + 多镜头提示词」，直接吐出带口型的整段戏。
- **分辨率是唯一旋钮**（480P / 720P / 1080P）：尺寸、度量深度、单价量级、是否自动重拍都由它带出来。
- **一把 `DASHSCOPE_API_KEY` 跑通全系统**；花费到上限就停下问人，不静默少出片。

## 多模态 Agent 编排

同一个 run 两种走法、**一份执行器**：分步（面板 / `fastvideo3 step`）或图（`fastvideo3 graph`）。
缺口由 `core/progress.py` 从盘上算，执行只走 `core/stages.py` 这一份装配。

```mermaid
flowchart LR
    S["剧本"] --> A["角色图 ‖ 场景图"]
    A --> V["场景视频<br/>立绘+场景图+音色样本+提示词<br/>→ 一次调用出画面·语音·口型"]
    V --> C["成片<br/>剪辑 → 一致性度量 → 闸门 → 终审"]
    C --> G{"人审"}
    G -- 点名重出某几组 --> V
    G -- 收片 --> F(["final.mp4"])
```

| 步骤        | 产出                                   | 模型                                 | 人能做什么                                              |
| ----------- | -------------------------------------- | ------------------------------------ | ------------------------------------------------------- |
| ① 剧本     | `script.json`                        | `qwen3.7-flash`                    | 编辑剧本稿（任意排版都能存）· 按意见重写 · 删除重生成 |
| ② 角色图   | `assets/char_*.png`                  | `wan2.7-image`                     | 生成 / 恢复 / 上传 / 改外貌描述（立绘是全片身份锚点）   |
| ③ 场景图   | `assets/scene_*.png`                 | `wan2.7-image`                     | 同上；长场景拆出的多段共用同一张场景图                  |
| ④ 场景视频 | `clips/scene_*.mp4` + 同名 `.json` | `wan3.0-video` · `cosyvoice-v2` | 改提示词、增删参考图、改时长、只重出某一组              |
| ⑤ 成片     | `final/final.mp4` + 字幕 + 度量报告  | FFmpeg + `qwen-vl-plus`            | 看片、点名重出、改字幕后只重跑剪辑                      |

## 快速开始：新机器 → Web 面板

面板是主路径。三条命令打开浏览器，从填 KEY 到出片全程不碰命令行：

```bash
./scripts/setup.sh                                       # Linux / macOS（Windows: .\scripts\setup.ps1）
conda activate fastvideo3                                # 新开终端都要这句 —— conda 环境不在项目目录里
fastvideo3 serve                                         # → http://127.0.0.1:8000
```

**不用再补 `pip install -e ".[web]"`** —— setup 把起面板要的东西都装了：`[2/6]` 按
`requirements.lock.txt` 装依赖（锁里已含 `fastapi==0.141.1` + `uvicorn==0.53.0`）；`[4/6]` 的
`pip install -e .` 只为给你 `fastvideo3` 这个命令名（`pyproject` 的 `[project.scripts]`），
不装也能在仓库根用 `python -m uvicorn fastvideo3.app.api:app --port 8000` 起同一个面板；
`[6/6]` 建前端 + provision。跳过 setup 手工装时才需要 `pip install -e ".[web]"`（写 `-e .` 不带 FastAPI）。

唯一的额外硬前提是 **node/npm**：前端产物 `web/dist` 不入库。机器上没 node 就只有 API、没有界面
（`serve` 照样起来并提醒 `cd web && npm ci && npm run build`）。

### `fastvideo3 serve` 起的是"一个进程两件事"

`app/api.py`（FastAPI）出全部 REST 接口，同时**同源托管** `web/dist` 的 Vue 3 产物 —— 不用另起
node 服务，没有第二个端口，也没有跨域。默认 `127.0.0.1:8000`，几个变体：

```bash
fastvideo3 serve --reload                     # 改后端代码自动重启
fastvideo3 serve --host 0.0.0.0 --port 8710   # 对外/换端口（局域网里另一台机器打开）
cd web && npm run dev                         # 改前端要热更新：→ :5173，/api 自动代理到 :8000
```

前端最终仍走 `npm run build` 的产物。`index.html` 带 `Cache-Control: no-cache`（内容寻址的
`/assets/*` 才给长期缓存），所以构建完普通刷新就是新版 —— 这是踩过的坑：以前没有这个头，浏览器
启发式缓存住旧 `index.html`，界面看起来像"功能没做"。

### 浏览器里从 0 到一条成片

| # | 在面板上点什么 | 打到的接口 |
| - | -------------- | ---------- |
| 1 | 顶栏「环境自检」：看 KEY / ffmpeg / 模型开通状态，缺运行时点「📦 补齐项目内置运行时」 | `GET /api/doctor` · `POST /api/doctor/provision` |
| 2 | 「新建任务」→「模型选择」第一行是百炼 API KEY（掩码输入，点到别处或按「保存」即写进 `.env`），再按探活按钮 | `PUT /api/api-keys` · `POST /api/api-keys/probe`（真发一条最小请求，≈¥0.001） |
| 3 | 填主题 / 时长 / 档位 / 成本上限；先勾 **Fake** 就零成本走占位片（色块 + 静帧 + 静音），点「▶ 开始生成」 | `POST /api/runs` —— **只落 `run_meta.json`，不启动生成、不花钱** |
| 4 | 详情页「▶ 开始生成 · <当前步>」补一步，五步点五次；跑起来后 3s 轮询自己翻进度 | `POST /api/runs/{run}/step`（后台子进程跑 `cli step`）· `GET .../steps` |
| 5 | 制作看板上每步之间介入：改剧本稿 / 按意见重写 / 上传换角色图与场景图 / 候选定妆照转正 / 改场景提示词 / 只重出某一组 | `PUT .../script/text` · `POST .../script/regenerate` · `PUT .../artifacts/{stage}/{name}` · `POST .../characters/{id}/portrait` · `PUT .../scenes/{id}/prompt` · `POST .../scene-groups/{gid}/generate` |
| 6 | 花到上限会红幅停下问人：点「继续生成…」抬新上限，已出产物一个不动、不重复花钱 | `POST .../budget/continue`（不确认时 `step` 直接回 409） |
| 7 | 第五步补完 → 看板里播 `final.mp4`、可下载；只想重剪就删成片再补第五步，零 API 费 | `GET /api/files/{run}/final/final.mp4` · `DELETE .../final` |

界面上一定会撞到的三条规矩：**全局单任务锁**（一次只跑一个生成任务，撞上了 409 会告诉你在跑哪个
run、哪一步）· **密钥只进本机 `.env`，接口只回"有没有配"**（`GET /api/api-keys` 出的是 bool，
`PUT` 挡跨站请求，且生成中不许换 KEY）· **降级必须响亮**（免费 edge-tts 顶上、参考图被丢弃等都进
`degradations.json` 并显示在看板上）。

## 命令行（与面板同一份执行器）

不想开浏览器也能走同一条流水线：缺口同样由 `core/progress.py` 从盘上算，执行只走 `core/stages.py`
这一份装配，所以**面板建的任务可以命令行接着补、命令行跑到一半可以回面板点**，交替不冲突。

```bash
fastvideo3 new --topic "校园喜剧" --duration 30 --fake    # Fake：零成本、无需 KEY
fastvideo3 step <run_id>                                 # 点一次补一步，共 5 次

fastvideo3 doctor --probe                                # 真跑前先探活（欠费/未开通别等烧钱才知道）
fastvideo3 new --topic "职场新人的第一天" --resolution 720P --budget 150
fastvideo3 step <run_id>                                 # 到上限会停下问人：
fastvideo3 budget-continue <run_id> 200                  #   抬上限，从停下处接着跑
```

常用命令：

| 想做的事                             | 命令                                                                                     |
| ------------------------------------ | ---------------------------------------------------------------------------------------- |
| 按意见改剧本（只作废真被改到的镜头） | `fastvideo3 script-regen <run> --prompt "…" --mode revise`                            |
| 只重出一张图 / 一组视频              | `fastvideo3 asset-gen` · `fastvideo3 scene-gen`                                     |
| 进度 / 成本 / 降级 / 一致性          | `fastvideo3 cost <run>` · `consistency <run>` · `output/<run>/run_summary.json`  |
| 只重跑剪辑（零 API 费）/ 消融四臂    | `python scripts/recompose_final.py <run>` · `python scripts/run_ablation.py --fake` |

## 项目结构

```
fastvideo3/
├── core/       # 判据：config(档位) progress(缺口) stages(唯一装配) storage(产物+血缘+事件)
│               #   scenegroup/voiceref/voice_budget draft_norm+script_text cost/pricing/pause tasklock
├── modules/    # 执行：m1 剧本 → m9 度量（与教学章节 1:1；m4_scene 是当前主干）
├── providers/  # 供应商：base(能力位/协议) factory(装配) 各家 API + fake(离线冒烟)
├── graph/      # 编排：builder(节点与回边) nodes(只调执行器) state checkpointer
├── app/        # 入口：cli.py(Typer) · api.py(FastAPI) · streamlit_app.py(教学观测)
└── utils/      # ffmpeg · audio · image · faceid(SFace) · lipsync · matting · emotion
web/            # Vue 3：NewRunForm · RunList · RunDetail(+ProductionBoard+StepBar) · DoctorView
configs/        # default.yaml(=480P 本体) + profile_720P/1080P.yaml + ablations/
prompts/ scripts/
tests/          # 700+ 条离线用例（Fake 供应商，无需 KEY）
output/<run_id>/# script.json assets/ storyboard/ audio/ clips/ final/ qc/
                # cost.json events.jsonl lineage.json degradations.json run_summary.json
```

## 技术栈

| 层          | 选型                                                                                                                                                                                                        |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 语言 / 数据 | Python ≥ 3.11 · `asyncio` 全程异步 · Pydantic v2（剧本/资产/成本的唯一校验）                                                                                                                           |
| 编排        | LangGraph `StateGraph` + `interrupt()`；检查点 SQLite，或 PostgreSQL（`[postgres]` + Docker）                                                                                                         |
| 入口        | FastAPI + Uvicorn（`[web]`）· Typer + Rich · Vue 3 + Vite（产物由后端同源托管）                                                                                                                         |
| 生成模型    | `qwen3.7-flash` 文本 · `wan2.7-image` 文生图（带参考图 → 三档都靠它锁脸）· `wan3.0-video` 场景级生成（画面+语音+口型）· `cosyvoice-v2` 配音（降级免费 edge-tts 并留痕）· `qwen-vl-plus` 评审 |
| 本地        | FFmpeg（项目内 `bin/` 优先于系统 PATH）· Pillow · OpenCV/SFace 人脸度量                                                                                                                                 |
| 台账        | SQLite JobStore + JSON 文件：`cost.json` 逐条计费 · `events.jsonl` 全事件 · `lineage.json` 血缘 · `degradations.json` 降级                                                                       |
| HTTP        | httpx + tenacity 直连（不套 LLM 框架：请求形状、错误文本、计费口径都能直接读）                                                                                                                              |

**档位差异**（`GET /api/resolutions` 就是这张表；单价来自 `pricing.yaml`，`fastvideo3 refresh-prices` 回写）：

| 档位           | 成片尺寸   | 30 秒预估  | 锁脸 | 度量 | 自动重拍     | 立绘抽卡  |
| -------------- | ---------- | ---------- | ---- | ---- | ------------ | --------- |
| 480P 教学/试跑 | 540×960   | ≈¥10–16 | ✔   | 抽样 | ✘（只报告） | ✘        |
| 720P 交付      | 720×1280  | ≈¥23–35 | ✔   | 抽样 | ✔ ≤2 轮    | ✘        |
| 1080P 商业级   | 1080×1920 | ≈¥58–88 | ✔   | 全检 | ✔ ≤2 轮    | ✔ 2 候选 |

场景片段按输出秒计价 ¥0.3 / ¥0.6 / ¥1.2 —— **锁脸三档都开，重拍是唯一按档花钱的差别。**

## 开发者

```bash
pip install -e ".[dev]" && ruff check . && mypy fastvideo3
pytest          # 离线：单元 + Fake 全链路 + Web API（无需 KEY）
pytest -m api   # 真实 API 冒烟（需 .env）
cd web && npm ci && npm run build
```

三条硬规矩（都有测试钉着）：**同一事实只有一份实现** · **降级必须响亮**（进 `degradations.json`
并出现在看板上，只写日志等于没写）· **不覆盖人工上传的资产**（`uploads.json` 是硬边界）。

每条质量说法都能对着一条 run 核：`keyframe_gen{ref_count,ref_ids}`（首帧带没带那张角色图）·
`clips/scene_*.json` 的 `ref_images`/`dropped`（真发了什么、丢了谁）· `cost.json`（钱打在哪个模型上）·
`consistency_report.json` + `degradations.json`（度量与降级）。
