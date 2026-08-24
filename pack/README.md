# GPUStack 容器镜像构建说明(pack/)

本目录是 Docker 镜像构建的**打包目录**:构建上下文为仓库根目录,`pack/Dockerfile` 负责产出 GPUStack 容器镜像。

## 一、构建命令

一键构建(仓库根目录执行,已配置本地 UI 产物路径):

```bash
./build-cubestack-express.sh
# 等价于:
#   UI_LOCAL_PATH=/path/to/gpustack-ui/dist PACKAGE_TAG=latest make package
```

常用参数(见 `hack/package.sh`):

| 环境变量 | 默认 | 说明 |
|---|---|---|
| `PACKAGE_NAMESPACE` | gpustack | 镜像命名空间 |
| `PACKAGE_TAG` | dev | 镜像标签(如 latest) |
| `PACKAGE_ARCH` | 本机架构 | 目标架构(amd64/arm64) |
| `PACKAGE_UI_LOCAL_PATH` / `UI_LOCAL_PATH` | 空 | 本地前端 `dist` 路径;为空则构建期在线下载 UI |
| `PACKAGE_PUSH` | false | 构建后是否推送 |
| `PACKAGE_NO_CACHE` | false | true=禁用构建缓存(缓存损坏时用) |

> 前置:需要 Docker 或 Podman;镜像源类变量(如 base image)在 `pack/Dockerfile` 顶部 `ARG` 中定义。

## 二、pack/ 目录结构

```
pack/
├── Dockerfile          # 镜像构建脚本(38KB,多阶段:base → gpustack)
├── entrypoint.sh       # 容器入口脚本
├── rootfs/             # 附加 rootfs(s6 服务等)
└── downloads/          # ★ 离线依赖缓存(build context 的一部分,详见 downloads/README.md)
```

## 三、离线依赖(pack/downloads/)

构建期优先使用本地离线包,避免在线下载(国内网络慢/易失败)。**必需离线包缺失会导致构建失败**。

| 项 | 版本/文件 | Dockerfile 引用 | 必需? |
|---|---|---|---|
| s6-overlay | noarch + x86_64 tar.xz | L261(L274-289,有缓存则用,否则在线) | 可选缓存 |
| Go 工具链 | go1.23.3.linux-amd64.tar.gz | L423(L438) | 可选缓存 |
| skopeo 源码 | v1.20.0(git 检出) | L424(L443-472,本地编译) | 可选缓存 |
| worker 工具 | gpustack-tools(gguf-parser + fastfetch) | L544/L568(硬校验) | 必需 |
| Prometheus | prometheus-3.5.1.linux-amd64.tar.gz | L492/L516 | 必需 |
| Grafana | grafana-12.2.4.linux-amd64.tar.gz | L493/L523 | 必需 |

备用(已下载但 Dockerfile 未直接引用):`mindie-atb-models_2.1.rc1_*`(amd64/arm64)、`community-inference-backends/`(社区推理后端源码副本)。

> **完整清单、大小与用途对应关系见 `downloads/README.md`。**

## 四、版本对齐与升级

- 版本由 `pack/Dockerfile` 顶部 `ARG` 决定:`PROMETHEUS_VERSION`、`GRAFANA_VERSION`、`S6_OVERLAY_VERSION`、Go、skopeo 等;
- `COPY` 按 **精确文件名** 匹配(`prometheus-${PROMETHEUS_VERSION}.linux-${TARGETARCH}.tar.gz` 等),升级版本时必须:
  1. 修改 `Dockerfile` 的 `ARG`;
  2. 下载对应版本 tar 包替换 `downloads/` 下文件(文件名保持一致);
  3. 重新 `make package`;
- 多架构构建:按 `TARGETARCH` 命名补全 amd64/arm64 的 tar 包(`tools`、`prometheus`、`grafana` 均按 `linux-${TARGETARCH}` 匹配);
- `PACKAGE_NO_CACHE=true` 可在缓存损坏时全量重建。

## 五、其他说明

- UI 前端产物默认构建期在线下载;离线环境请用 `UI_LOCAL_PATH` 指定本地 `dist`(见 `build-cubestack-express.sh`);
- 镜像源(`harbor.isuanova.com` 等)与版本参数集中在 Dockerfile 顶部,便于替换为内网镜像源。
