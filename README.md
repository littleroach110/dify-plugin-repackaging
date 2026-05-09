## Dify Plugin Downloading and Repackaging (uv-compatible fork)

**English** | [中文](README_CN.md)

> **Fork of [junjiem/dify-plugin-repackaging](https://github.com/junjiem/dify-plugin-repackaging)**
> with improvements for Dify 1.x plugins that use **uv** as the package manager.
> Additional reference: [xcsf/dify-plugin-repackaging-python](https://github.com/xcsf/dify-plugin-repackaging-python).

### What's improved in this fork

The original project used `pip download` for wheel packaging. Modern Dify plugins
(`pyproject.toml` + `uv`) broke this flow in several ways — this fork fixes them:

| # | Issue | Fix |
|---|-------|-----|
| 1 | `[tool.uv]` offline config (`no-index`, `find-links`) was injected into `pyproject.toml` **before** `uv lock`, so `uv lock` immediately failed — no index, no local wheels yet | Move injection to **after** wheel download; `uv lock` runs cleanly online first |
| 2 | `pip download --only-binary=:all:` silently excluded sdist-only pure-Python packages (e.g. `docopt`) causing download failure | Prefer `uv pip download`; if cross-platform download fails, retry without `--python-platform` to capture sdist-only packages; pip fallback uses `--no-deps` on the second pass |
| 3 | `uv pip download` subcommand not available in older uv builds; script hard-failed | Added `uv pip download --help` capability probe; falls back to pip when unavailable |
| 4 | `curl` exits 0 even on HTTP 4xx/5xx, so an error-page HTML was silently passed to `unzip` | Added HTTP status-code check (`-w "%{http_code}"`) and `unzip -t` integrity validation before extraction |
| 5 | `uv lock` does not accept `--python-platform` or `--python-version` (only `uv export` / `uv pip` do); lock step failed for any plugin that ships both `pyproject.toml` and `requirements.txt` | Removed `--python-platform` from `uv lock`; replaced `--python-version` with `--python` |
| 6 | Offline `uv lock` regeneration failed for plugins with dev dependencies (e.g. `black`, `pytest`) because dev packages are not downloaded as wheels | Removed offline re-lock entirely — wheels downloaded from PyPI carry the same hashes as the original `uv.lock`, so no regeneration is needed; added `--no-dev` to `uv export` to exclude dev deps from the wheel set |
| 7 | Plugins ship a `uv.lock` generated inside a Dify dev environment where `dify-plugin` is pre-installed; that lock omits its transitive deps (e.g. `socksio`), so `uv sync` at runtime fails with `no-index = true` | Always run `uv lock` (even when `uv.lock` already exists) to update the lock incrementally — existing pinned versions are preserved, missing transitive deps are added; then regenerate `requirements.txt` via `uv export` for the complete set |
| 8 | `uv pip download` uses `--python-version` (target Python version for marker evaluation), not `--python` (interpreter path); using the wrong flag caused uv download to fail silently and fall back to pip, which then choked on C-extension sdists (e.g. `greenlet`) | Reverted `uv pip download` to `--python-version`; only `uv lock` and `uv export` use `--python` (those are the commands where `--python-version` was removed in uv 0.11.x) |
| 11 | No post-download verification: if any wheel was silently omitted the script packaged a broken plugin anyway, only failing at runtime on the air-gapped server | Added a coverage-check loop after all download steps: every line in `requirements.txt` is matched against `./wheels/`; any missing package aborts packaging with a clear error rather than producing a silently broken artifact |
| 10 | `uv pip download --python-platform <X>` silently skips `py3-none-any` (pure-Python) wheels — they have no platform tag so uv omits them in cross-platform mode; and pip's second pass only runs when pass 1 fails, so if the plugin has no C-extension failures the none-any packages are never caught | Always run two uv passes when cross-platform is specified (pass 1 with `--python-platform`, pass 2 without); additionally, always run a **pip safety-net pass** (`--only-binary` then `--no-deps`, both without platform constraint) after any primary download — this guarantees none-any wheels and sdist-only pure-Python packages reach `./wheels/` regardless of how the primary download behaved |
| 9 | GitHub Actions workflow exported `PIP_PLATFORM=manylinux_2_17_x86_64` into `$GITHUB_ENV`; pip reads `PIP_<OPTION>` env vars automatically, so `--platform manylinux_2_17_x86_64` was applied to **every** pip invocation — including the "no-platform" second pass and build-dependency subprocesses — causing C-extension sdist builds to fail; additionally, some CI environments ship an older uv that lacks `uv pip download`, so the probe must be retained | Renamed workflow env var from `PIP_PLATFORM` to `TARGET_PLATFORM` (avoids pip auto-config); kept the `uv pip download --help` capability probe so older uv falls back to pip; in the pip second pass use `env -u PIP_PLATFORM` to explicitly clear any inherited platform constraint for that subprocess |

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
