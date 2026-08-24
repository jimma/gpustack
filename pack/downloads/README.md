# pack/downloads —— 离线依赖包清单(Docker 构建上下文)

本目录是 `pack/Dockerfile` 构建时的**离线依赖缓存**(build context 的一部分):优先使用本地文件,避免构建期在线下载(国内网络环境下在线拉取慢/易失败)。

> 说明:文件名与 `Dockerfile` 中的版本变量**精确匹配**,升级版本时必须同步替换对应文件并保持文件名一致,否则 `COPY` 会失败。

---

## 一、Dockerfile 实际使用的文件(6 项)

| 文件/目录 | 大小 | 内容 | Dockerfile 中的用途 |
|---|---|---|---|
| `s6-overlay/` | 约 660 KB | s6-overlay-noarch.tar.xz + s6-overlay-x86_64.tar.xz | `COPY pack/downloads/s6-overlay/ /tmp/s6-local/`(L261),构建期若本地缓存存在则直接使用,否则在线下载(L274-289)。用于 s6 init 进程管理 |
| `go/` | 73 MB | go1.23.3.linux-amd64.tar.gz | `COPY pack/downloads/go/ /tmp/go-local/`(L423),作为 Go 工具链(L438),用于本地编译 skopeo |
| `skopeo/skopeo/` | 源码树 | skopeo v1.20.0 源码(git 检出) | `COPY pack/downloads/skopeo/skopeo /tmp/skopeo-local/`(L424),检测到 `Makefile` 则本地编译(L443-472);用于容器镜像拷贝工具 |
| `tools/` | 7 MB | gpustack-tools-linux-amd64.tar.gz(内含 `gguf-parser` + `fastfetch` + versions.json) | `COPY pack/downloads/tools/ /tmp/gpustack-tools/`(L544),按 `TARGETARCH` 解压(L568),并硬校验 worker 依赖存在(L577-584) |
| `prometheus/` | 121 MB | prometheus-3.5.1.linux-amd64.tar.gz | `COPY pack/downloads/prometheus/prometheus-${PROMETHEUS_VERSION}...`(L492),解压到 /opt/prometheus 并建软链(L516-519) |
| `grafana/` | 189 MB | grafana-12.2.4.linux-amd64.tar.gz | `COPY pack/downloads/grafana/grafana-${GRAFANA_VERSION}...`(L493),解压到 /opt/grafana 并建软链(L523-529) |

> 版本变量:见 Dockerfile 顶部 `ARG` —— `PROMETHEUS_VERSION=3.5.1`、`GRAFANA_VERSION=12.2.4`、`S6_OVERLAY_VERSION=3.2.1.0`、Go 1.23.3;skopeo 为 v1.20.0。

---

## 二、已下载但当前 Dockerfile 未直接引用(备用/预留)

| 文件/目录 | 大小 | 说明 |
|---|---|---|
| `mindie-atb-models_2.1.rc1_linux-amd64_py3.11_torch2.1.0-abi0.tar.gz` | 5.9 MB | MindIE(昇腾)ATB 模型包(amd64),**未在 Dockerfile 中引用** |
| `mindie-atb-models_2.1.rc1_linux-arm64_py3.11_torch2.1.0-abi0.tar.gz` | 5.9 MB | 同上(arm64),**未引用** |
| `community-inference-backends/` | 仓库副本 | GPUStack 社区推理后端(llama.cpp / mineru / tensorrt-llm / text-embeddings-inference 等)源码副本,**未直接引用** |

---

## 三、与构建无关

| 文件/目录 | 说明 |
|---|---|
| `.claude/settings.local.json` | Claude Code 本地工具配置,与 Docker 构建无关 |

---

## 四、维护提示

1. **更新版本流程**:改 `Dockerfile` 的 `ARG` 版本号 → 下载对应版本 tar 包放入本目录(文件名与 COPY 一致)→ 重新构建;
2. 新增架构(如 arm64)时,按 `TARGETARCH` 规则补充对应 tar 包(`tools`、`prometheus`、`grafana` 等均按 `linux-${TARGETARCH}` 命名);
3. s6-overlay / go / skopeo 属于“有本地缓存则用、无则在线拉取”的**可选缓存**,可删;prometheus / grafana / tools 属于**必需离线包**,缺失会导致构建失败;
4. 目录内 `go`、`tools` 等为 2026-08-24 生成,注意与 Dockerfile 版本对齐后再提交。
