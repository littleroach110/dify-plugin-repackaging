## Dify Plugin Downloading and Repackaging (uv-compatible fork)

> **Fork of [junjiem/dify-plugin-repackaging](https://github.com/junjiem/dify-plugin-repackaging)**
> with improvements for Dify 1.x plugins that use **uv** as the package manager.
> Additional reference: [xcsf/dify-plugin-repackaging-python](https://github.com/xcsf/dify-plugin-repackaging-python).

### What's improved in this fork

The original project used `pip download` for wheel packaging. Modern Dify plugins
(`pyproject.toml` + `uv`) broke this flow in several ways — this fork fixes them:

| Issue | Fix |
|-------|-----|
| `[tool.uv]` offline config was injected **before** `uv lock`, causing `uv lock` to fail (no index, no wheels) | Injection is now done **after** wheels are downloaded |
| Bundled `uv.lock` had hashes from the online index; `uv sync` at runtime rejected them | `uv lock` is re-run offline after wheel download so hashes match exactly |
| `pip download --only-binary=:all:` silently excluded sdist-only pure-Python packages (e.g. `docopt`) | Two-pass download: `uv pip download` with platform, then retry without `--python-platform` for sdist-only packages; pip fallback uses `--no-deps` |
| `curl` returned exit code 0 on HTTP 4xx/5xx; script proceeded with an invalid file | HTTP status code check + `unzip -t` integrity validation before extraction |

---

### How To Use With Github Action
1. Fork this repository
2. Open the GitHub page of your forked repository
3. Run workflow (Actions → Repackage Dify Plugin)

![run_github_action_1](images/run_github_action_1.png)
![run_github_action_2](images/run_github_action_2.png)

4. Download artifact

![run_github_action_3](images/run_github_action_3.png)

### How To Use With Docker

1. Change param in Dockerfile

```dockerfile
CMD ["./plugin_repackaging.sh", "-p", "manylinux_2_17_x86_64", "market", "antv", "visualization", "0.1.7"]
```

2. Build

```bash
docker build -t dify-plugin-repackaging .
```

3. Run

Linux
```bash
docker run -v $(pwd):/app dify-plugin-repackaging
```
Windows
```cmd
docker run -v %cd%:/app dify-plugin-repackaging
```

4. Override CMD (optional)

Linux
```bash
docker run -v $(pwd):/app dify-plugin-repackaging ./plugin_repackaging.sh -p manylinux_2_17_x86_64 market antv visualization 0.1.7
```

---

### Prerequisites

- **OS**: Linux amd64/aarch64, macOS x86_64/arm64
- **Python**: 3.12.x (same as `dify-plugin-daemon`)
- **uv**: recommended (`pip install uv`); required for `pyproject.toml`-based plugins

> **Note**: The script uses `yum` to install `unzip` on RPM-based systems. On other
> distributions, install `unzip` in advance.

#### Clone

```shell
git clone https://github.com/littleroach110/dify-plugin-repackaging.git
```

---

### Description

#### From the Dify Marketplace

![market](images/market.png)

##### Example

```shell
./plugin_repackaging.sh market langgenius agent 0.0.9
```

![langgenius-agent](images/langgenius-agent.png)

#### From GitHub

![github](images/github.png)

##### Example

```shell
./plugin_repackaging.sh github junjiem/dify-plugin-agent-mcp_sse 0.0.1 agent-mcp_see.difypkg
```

![junjiem-mcp_sse](images/junjiem-mcp_sse.png)

#### Local .difypkg repackaging

![local](images/local.png)

##### Example

```shell
./plugin_repackaging.sh local ./db_query.difypkg
```

![db_query](images/db_query.png)

#### Cross-platform repackaging

Use `-p` with a pip platform string to build for a different target OS/arch than the current machine.

| Target | Flag |
|--------|------|
| Linux x86_64 | `-p manylinux_2_17_x86_64` |
| Linux arm64  | `-p manylinux_2_17_aarch64` |

---

### Update Dify platform settings / Dify 平台放开限制

- `.env`: set `FORCE_VERIFYING_SIGNATURE=false` — allows installing plugins not listed in the Dify Marketplace.
- `.env`: set `PLUGIN_MAX_PACKAGE_SIZE=524288000` — allows plugins up to 500 MB.
- `.env`: set `NGINX_CLIENT_MAX_BODY_SIZE=500M` — allows uploads up to 500 MB.

---

### Installing Plugins via Local / 通过本地安装插件

Visit the Dify platform's plugin management page and choose **Local Package File**.

访问 Dify 平台的插件管理页，选择通过本地插件完成安装。

![install_plugin_via_local](./images/install_plugin_via_local.png)

---

### Star history

[![Star History Chart](https://api.star-history.com/svg?repos=junjiem/dify-plugin-repackaging&type=Date)](https://star-history.com/#junjiem/dify-plugin-repackaging&Date)
