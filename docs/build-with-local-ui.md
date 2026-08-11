# 使用本地 UI 构建 GPUStack

## 概述

默认情况下，`make build` 和 `make package` 会从远程 CDN 下载 UI 资源:

```
https://gpustack-ui-1303613262.cos.accelerate.myqcloud.com/releases/<tag>.tar.gz
```

通过设置环境变量，可以改为使用本地 UI 构建产物，避免网络依赖。

## 环境变量速查

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UI_LOCAL_PATH` | 空 | 本地 UI dist 目录路径，设置后跳过远程下载 |
| `UI_DOWNLOAD` | `true` | 设为 `false` 完全跳过 UI（保留已有的 `gpustack/ui/`） |
| `COMMUNITY_BACKENDS_FORCE_UPDATE` | `false` | 设为 `true` 强制从远程重新拉取社区后端 |
| `COMMUNITY_BACKENDS_CACHE_DIR` | `pack/downloads/community-inference-backends/` | 社区后端缓存目录 |

---

## 一、本地构建 (`make build`)

### 1.1 使用本地 UI

```bash
UI_LOCAL_PATH=/home/jimma/data/code/suan/suan/frontend/gpustack-ui/dist make build
```

每次构建都会从该目录重新复制最新内容，不使用缓存。

本地 UI 目录结构要求（至少包含 `index.html`）:

```
gpustack-ui/dist/
├── index.html
├── favicon.ico
├── css/
├── js/
└── static/
```

### 1.2 跳过 UI 下载

如果 UI 没有变更，可以跳过下载直接复用已有的:

```bash
UI_DOWNLOAD=false make build
```

### 1.3 强制更新社区后端

社区后端默认缓存到 `pack/downloads/community-inference-backends/`（首次会自动 clone，后续只做增量 `git pull`）。如需强制从远程重新拉取:

```bash
COMMUNITY_BACKENDS_FORCE_UPDATE=true make build
```

---

## 二、Docker 镜像构建 (`make package`)

### 2.1 使用本地 UI

```bash
UI_LOCAL_PATH=/home/jimma/data/code/suan/suan/frontend/gpustack-ui/dist make package
```

构建流程:
1. 将本地 UI 目录复制到 `pack/.ui-local/`（构建上下文中）
2. 传递 `--build-arg UI_LOCAL_PATH=/workspace/gpustack/pack/.ui-local` 给 Docker
3. Dockerfile 中 `make build` 检测到 `UI_LOCAL_PATH` 从该路径复制 UI
4. 构建完成后自动清理 `pack/.ui-local/`

### 2.2 自定义镜像 tag

```bash
UI_LOCAL_PATH=/home/jimma/data/code/suan/suan/frontend/gpustack-ui/dist \
  PACKAGE_TAG=dev make package
```

生成的镜像: `gpustack/gpustack:dev`

### 2.3 构建并推送

```bash
UI_LOCAL_PATH=/home/jimma/data/code/suan/suan/frontend/gpustack-ui/dist \
  PACKAGE_TAG=v0.5.0 \
  PACKAGE_PUSH=true make package
```

### 2.4 Docker 镜像中使用远程 UI

不加 `UI_LOCAL_PATH` 即可，默认从远程 CDN 下载:

```bash
PACKAGE_TAG=dev make package
```

### 2.5 跳过 Docker 镜像中的 UI 下载

```bash
PACKAGE_UI_DOWNLOAD=false make package
```

---

## 三、常见问题

### Q: 构建报错 "local UI path ... does not exist"

确认前端项目已经构建并且路径正确:

```bash
ls /home/jimma/data/code/suan/suan/frontend/gpustack-ui/dist/index.html
```

### Q: 每次 `make package` 都很慢

Docker 构建首次需要下载基础镜像和依赖工具链（Go、PostgreSQL 等），后续构建会利用 Docker layer cache 和 `--cache-from` 加速。可以使用:

```bash
PACKAGE_WITH_CACHE=true make package
```

### Q: 如何在 Docker 镜像中使用完全离线的构建？

结合两个选项:

```bash
UI_LOCAL_PATH=/path/to/local/ui/dist \
  PACKAGE_UI_DOWNLOAD=false \
  COMMUNITY_BACKENDS_FORCE_UPDATE=false \
  make package
```
