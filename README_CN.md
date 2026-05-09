## Dify 插件下载与离线重打包（uv 兼容版 Fork）

**English** | [中文](README_CN.md)

> **Fork 自 [junjiem/dify-plugin-repackaging](https://github.com/junjiem/dify-plugin-repackaging)**，
> 针对使用 **uv** 作为包管理器的 Dify 1.x 插件进行了兼容性修复。
> 同时参考了 [xcsf/dify-plugin-repackaging-python](https://github.com/xcsf/dify-plugin-repackaging-python)。

### 本 Fork 的改进内容

原项目使用 `pip download` 完成 wheel 打包。现代 Dify 插件（`pyproject.toml` + `uv`）使原流程在多处失效，本 Fork 逐一修复：

| # | 问题 | 修复方式 |
|---|------|---------|
| 1 | `[tool.uv]` 离线配置（`no-index`、`find-links`）在 `uv lock` **之前**就注入到 `pyproject.toml`，导致 `uv lock` 立即失败——既无 index 又无本地 wheel | 将注入时机移到 wheel 下载**之后**；`uv lock` 先在联网状态下正常执行 |
| 2 | `pip download --only-binary=:all:` 会静默跳过只有 sdist 的纯 Python 包（如 `docopt`），导致下载失败 | 优先使用 `uv pip download`；跨平台下载失败时，去掉 `--python-platform` 重试以捕获 sdist-only 包；pip 回退路径的第二次下载使用 `--no-deps` |
| 3 | 旧版 uv 不支持 `uv pip download` 子命令，脚本直接报错退出 | 增加 `uv pip download --help` 能力探测；不可用时自动回退到 pip |
| 4 | `curl` 在 HTTP 4xx/5xx 时仍返回退出码 0，错误响应的 HTML 页面被静默传给 `unzip` | 增加 HTTP 状态码检查（`-w "%{http_code}"`）和 `unzip -t` 完整性校验，在解压前拦截无效文件 |
| 5 | `uv lock` 不接受 `--python-platform` 和 `--python-version` 参数（这两个参数只属于 `uv export` / `uv pip`）；同时包含 `pyproject.toml` 和 `requirements.txt` 的插件在锁定步骤失败 | 从 `uv lock` 调用中移除 `--python-platform`；将 `--python-version` 替换为 `--python` |
| 6 | 离线 `uv lock` 重新生成时，因 dev 依赖（如 `black`、`pytest`）未被下载为 wheel 而失败 | 完全移除离线重锁步骤——从 PyPI 下载的 wheel 与原始 `uv.lock` 中的 hash 完全一致，无需重新生成；同时为 `uv export` 添加 `--no-dev` 以排除 dev 依赖的下载 |
| 7 | 插件自带的 `uv.lock` 通常在 Dify 开发环境中生成，那里 `dify-plugin` 已预装，因此锁文件缺少其传递依赖（如 `socksio`），导致运行时 `uv sync` 在 `no-index = true` 下报依赖不满足 | 始终执行 `uv lock`（即使 `uv.lock` 已存在），以增量方式更新锁文件——已锁定的版本保持不变，缺失的传递依赖被补全；再通过 `uv export` 生成完整的 requirements.txt |
| 8 | `uv pip download` 使用 `--python-version`（指定目标 Python 版本用于 marker 求值），而非 `--python`（指定解释器路径）；误用 `--python` 导致 uv 下载静默失败，回退到 pip，pip 再在 C 扩展 sdist（如 `greenlet`）上报错 | 将 `uv pip download` 恢复为 `--python-version`；只有 `uv lock` 和 `uv export` 使用 `--python`（这两个命令在 uv 0.11.x 中移除了 `--python-version`） |
| 10 | `uv pip download --python-platform <X>` 会静默跳过 `py3-none-any`（纯 Python）的 wheel——因其无平台标签，uv 在 cross-platform 模式下不下载它们；`pydantic-settings` 等包因此不在 `./wheels/` 中，运行时 `uv sync` 尝试联网下载但超时失败 | 指定了目标平台时始终运行两遍：第一遍带 `--python-platform`（获取目标平台 binary wheel），第二遍不带（补全所有 `none-any` 包及第一遍遗漏的包；已存在的文件会被自动跳过） |
| 9 | GitHub Actions workflow 将 `PIP_PLATFORM=manylinux_2_17_x86_64` 写入 `$GITHUB_ENV`；pip 会自动读取 `PIP_<选项名>` 格式的环境变量，导致**所有** pip 调用（包括本应无平台约束的第二遍和构建依赖子进程）都附带 `--platform manylinux_2_17_x86_64`，最终触发 C 扩展 sdist 构建失败；此外，部分 CI 环境中的 uv 版本较旧，不支持 `uv pip download`，因此探测条件必须保留 | 将 workflow 环境变量从 `PIP_PLATFORM` 改名为 `TARGET_PLATFORM`（避开 pip 的 `PIP_<选项名>` 自动配置机制）；保留 `uv pip download --help` 探测条件，旧版 uv 可正确回退到 pip；pip 第二遍中使用 `env -u PIP_PLATFORM` 显式清除继承的平台约束环境变量 |

---

### 通过 GitHub Actions 使用

1. Fork 本仓库
2. 打开你 Fork 后的 GitHub 仓库页面
3. 运行工作流（Actions → Repackage Dify Plugin）

![run_github_action_1](images/run_github_action_1.png)
![run_github_action_2](images/run_github_action_2.png)

4. 下载构建产物

![run_github_action_3](images/run_github_action_3.png)

### 通过 Docker 使用

1. 修改 Dockerfile 中的参数

```dockerfile
CMD ["./plugin_repackaging.sh", "-p", "manylinux_2_17_x86_64", "market", "antv", "visualization", "0.1.7"]
```

2. 构建镜像

```bash
docker build -t dify-plugin-repackaging .
```

3. 运行容器

Linux
```bash
docker run -v $(pwd):/app dify-plugin-repackaging
```
Windows
```cmd
docker run -v %cd%:/app dify-plugin-repackaging
```

4. 覆盖默认命令（可选）

Linux
```bash
docker run -v $(pwd):/app dify-plugin-repackaging ./plugin_repackaging.sh -p manylinux_2_17_x86_64 market antv visualization 0.1.7
```

---

### 前置条件

- **操作系统**：Linux amd64/aarch64，macOS x86_64/arm64
- **Python**：3.12.x（与 `dify-plugin-daemon` 保持一致）
- **uv**：推荐安装（`pip install uv`）；`pyproject.toml` 类型的插件必须安装

> **注意**：脚本在 RPM 系发行版（如 CentOS、Fedora）上会通过 `yum` 安装 `unzip`。其他发行版请提前手动安装 `unzip`。

#### 克隆仓库

```shell
git clone https://github.com/littleroach110/dify-plugin-repackaging.git
```

---

### 用法说明

#### 从 Dify Marketplace 下载并重打包

![market](images/market.png)

##### 示例

```shell
./plugin_repackaging.sh market langgenius agent 0.0.9
```

![langgenius-agent](images/langgenius-agent.png)

#### 从 GitHub 下载并重打包

![github](images/github.png)

##### 示例

```shell
./plugin_repackaging.sh github junjiem/dify-plugin-agent-mcp_sse 0.0.1 agent-mcp_see.difypkg
```

![junjiem-mcp_sse](images/junjiem-mcp_sse.png)

#### 对本地 .difypkg 文件重打包

![local](images/local.png)

##### 示例

```shell
./plugin_repackaging.sh local ./db_query.difypkg
```

![db_query](images/db_query.png)

#### 跨平台重打包

使用 `-p` 参数指定目标平台，适用于构建机器与运行环境架构不同的场景。

| 目标平台 | 参数 |
|---------|------|
| Linux x86_64 | `-p manylinux_2_17_x86_64` |
| Linux arm64  | `-p manylinux_2_17_aarch64` |

---

### Dify 平台配置 / Update Dify platform settings

- `.env`：将 `FORCE_VERIFYING_SIGNATURE` 改为 `false`，允许安装未在 Dify Marketplace 上架的插件。
- `.env`：将 `PLUGIN_MAX_PACKAGE_SIZE` 改为 `524288000`，允许安装最大 500 MB 的插件。
- `.env`：将 `NGINX_CLIENT_MAX_BODY_SIZE` 改为 `500M`，允许上传最大 500 MB 的内容。

---

### 通过本地文件安装插件 / Installing Plugins via Local

访问 Dify 平台的插件管理页，选择**本地插件文件**完成安装。

Visit the Dify platform's plugin management page and choose **Local Package File**.

![install_plugin_via_local](./images/install_plugin_via_local.png)

---

### Star 历史

[![Star History Chart](https://api.star-history.com/svg?repos=junjiem/dify-plugin-repackaging&type=Date)](https://star-history.com/#junjiem/dify-plugin-repackaging&Date)
