#!/bin/bash
# author: Junjie.M

DEFAULT_GITHUB_API_URL=https://github.com
DEFAULT_MARKETPLACE_API_URL=https://marketplace.dify.ai
DEFAULT_PIP_MIRROR_URL=https://mirrors.aliyun.com/pypi/simple

GITHUB_API_URL="${GITHUB_API_URL:-$DEFAULT_GITHUB_API_URL}"
MARKETPLACE_API_URL="${MARKETPLACE_API_URL:-$DEFAULT_MARKETPLACE_API_URL}"
PIP_MIRROR_URL="${PIP_MIRROR_URL:-$DEFAULT_PIP_MIRROR_URL}"

CURR_DIR=`dirname $0`
cd $CURR_DIR || exit 1
CURR_DIR=`pwd`
USER=`whoami`
ARCH_NAME=`uname -m`
OS_TYPE=$(uname)
OS_TYPE=$(echo "$OS_TYPE" | tr '[:upper:]' '[:lower:]')

CMD_NAME="dify-plugin-${OS_TYPE}-amd64"
if [[ "arm64" == "$ARCH_NAME" || "aarch64" == "$ARCH_NAME" ]]; then
	CMD_NAME="dify-plugin-${OS_TYPE}-arm64"
fi

# Cross packaging / resolution controls
PIP_PLATFORM=""
RAW_PLATFORM=""    # raw value from -p, e.g. manylinux2014_x86_64
PACKAGE_SUFFIX="offline"
PRERELEASE_ALLOW=0

market(){
	if [[ -z "$2" || -z "$3" || -z "$4" ]]; then
		echo ""
		echo "Usage: "$0" market [plugin author] [plugin name] [plugin version]"
		echo "Example:"
		echo "	"$0" market junjiem mcp_sse 0.0.1"
		echo "	"$0" market langgenius agent 0.0.9"
		echo ""
		exit 1
	fi
	PLUGIN_AUTHOR=$2
	PLUGIN_NAME=$3
	PLUGIN_VERSION=$4
	PLUGIN_PACKAGE_PATH=${CURR_DIR}/${PLUGIN_AUTHOR}-${PLUGIN_NAME}_${PLUGIN_VERSION}.difypkg
	PLUGIN_DOWNLOAD_URL=${MARKETPLACE_API_URL}/api/v1/plugins/${PLUGIN_AUTHOR}/${PLUGIN_NAME}/${PLUGIN_VERSION}/download

	echo ""
	echo "=========================================="
	echo "Downloading from Dify Marketplace"
	echo "=========================================="
	echo "Author: ${PLUGIN_AUTHOR}"
	echo "Plugin: ${PLUGIN_NAME}"
	echo "Version: ${PLUGIN_VERSION}"
	echo "URL: ${PLUGIN_DOWNLOAD_URL}"

	HTTP_STATUS=$(curl -L -w "%{http_code}" -o "${PLUGIN_PACKAGE_PATH}" "${PLUGIN_DOWNLOAD_URL}")
	if [[ $? -ne 0 ]] || [[ "${HTTP_STATUS}" != "200" ]]; then
		echo "✗ Error: Download failed (HTTP ${HTTP_STATUS})"
		echo "  Please check the plugin author, name, and version"
		echo "  URL: ${PLUGIN_DOWNLOAD_URL}"
		rm -f "${PLUGIN_PACKAGE_PATH}"
		exit 1
	fi

	DOWNLOADED_SIZE=$(du -h "${PLUGIN_PACKAGE_PATH}" | cut -f1)
	if ! unzip -t "${PLUGIN_PACKAGE_PATH}" &> /dev/null; then
		echo "✗ Error: Downloaded file is not a valid .difypkg archive (${DOWNLOADED_SIZE})"
		echo "  The server may have returned an error page instead of the plugin"
		rm -f "${PLUGIN_PACKAGE_PATH}"
		exit 1
	fi
	echo "✓ Downloaded successfully (${DOWNLOADED_SIZE})"

	repackage ${PLUGIN_PACKAGE_PATH}
}

github(){
	if [[ -z "$2" || -z "$3" || -z "$4" ]]; then
		echo ""
		echo "Usage: "$0" github [Github repo] [Release title] [Assets name (include .difypkg suffix)]"
		echo "Example:"
		echo "	"$0" github junjiem/dify-plugin-tools-dbquery v0.0.2 db_query.difypkg"
		echo "	"$0" github https://github.com/junjiem/dify-plugin-agent-mcp_sse 0.0.1 agent-mcp_see.difypkg"
		echo ""
		exit 1
	fi
	GITHUB_REPO=$2
	if [[ "${GITHUB_REPO}" != "${GITHUB_API_URL}"* ]]; then
		GITHUB_REPO="${GITHUB_API_URL}/${GITHUB_REPO}"
	fi
	RELEASE_TITLE=$3
	ASSETS_NAME=$4
	PLUGIN_NAME="${ASSETS_NAME%.difypkg}"
	PLUGIN_PACKAGE_PATH=${CURR_DIR}/${PLUGIN_NAME}-${RELEASE_TITLE}.difypkg
	PLUGIN_DOWNLOAD_URL=${GITHUB_REPO}/releases/download/${RELEASE_TITLE}/${ASSETS_NAME}

	echo ""
	echo "=========================================="
	echo "Downloading from GitHub"
	echo "=========================================="
	echo "Repository: ${GITHUB_REPO}"
	echo "Release: ${RELEASE_TITLE}"
	echo "Asset: ${ASSETS_NAME}"
	echo "URL: ${PLUGIN_DOWNLOAD_URL}"

	HTTP_STATUS=$(curl -L -w "%{http_code}" -o "${PLUGIN_PACKAGE_PATH}" "${PLUGIN_DOWNLOAD_URL}")
	if [[ $? -ne 0 ]] || [[ "${HTTP_STATUS}" != "200" ]]; then
		echo "✗ Error: Download failed (HTTP ${HTTP_STATUS})"
		echo "  Please check the GitHub repo, release title, and asset name"
		echo "  URL: ${PLUGIN_DOWNLOAD_URL}"
		rm -f "${PLUGIN_PACKAGE_PATH}"
		exit 1
	fi

	DOWNLOADED_SIZE=$(du -h "${PLUGIN_PACKAGE_PATH}" | cut -f1)
	if ! unzip -t "${PLUGIN_PACKAGE_PATH}" &> /dev/null; then
		echo "✗ Error: Downloaded file is not a valid .difypkg archive (${DOWNLOADED_SIZE})"
		echo "  The server may have returned an error page instead of the plugin"
		rm -f "${PLUGIN_PACKAGE_PATH}"
		exit 1
	fi
	echo "✓ Downloaded successfully (${DOWNLOADED_SIZE})"

	repackage ${PLUGIN_PACKAGE_PATH}
}

_local(){
	echo $2
	if [[ -z "$2" ]]; then
		echo ""
		echo "Usage: "$0" local [difypkg path]"
		echo "Example:"
		echo "	"$0" local ./db_query.difypkg"
		echo "	"$0" local /root/dify-plugin/db_query.difypkg"
		echo ""
		exit 1
	fi
	PLUGIN_PACKAGE_PATH=`realpath $2`
	repackage ${PLUGIN_PACKAGE_PATH}
}

repackage(){
	local PACKAGE_PATH=$1
	PACKAGE_NAME_WITH_EXTENSION=`basename ${PACKAGE_PATH}`
	PACKAGE_NAME="${PACKAGE_NAME_WITH_EXTENSION%.*}"

	echo ""
	echo "=========================================="
	echo "Dify Plugin Repackaging Tool"
	echo "=========================================="
	echo "Source: ${PACKAGE_PATH}"
	echo "Work directory: ${CURR_DIR}/${PACKAGE_NAME}"

	# Extract plugin package
	echo ""
	echo "Extracting plugin package..."
	install_unzip
	unzip -o ${PACKAGE_PATH} -d ${CURR_DIR}/${PACKAGE_NAME}
	if [[ $? -ne 0 ]]; then
		echo "✗ Error: Failed to extract package"
		exit 1
	fi
	echo "✓ Package extracted successfully"

	cd ${CURR_DIR}/${PACKAGE_NAME} || exit 1
	if [ ! -f "pyproject.toml" ] && [ ! -f "requirements.txt" ]; then
		echo "⚠ Warning: No pyproject.toml or requirements.txt found"
	fi

	# Inject [tool.uv] config into pyproject.toml (runtime will use local wheels offline)
	inject_uv_into_pyproject() {
		local PYFILE="$1"
		[ -f "$PYFILE" ] || return 0
	awk '
		BEGIN { in_uv=0; saw_uv=0; saw_no=0; saw_find=0; saw_pre=0 }
		function print_missing(){ if (!saw_no) print "no-index = true"; if (!saw_find) print "find-links = [\"./wheels\"]"; if (!saw_pre) print "prerelease = \"allow\"" }
		/^[ \t]*\[tool\.uv\][ \t]*$/ { saw_uv=1; in_uv=1; saw_no=0; saw_find=0; saw_pre=0; print; next }
		{ if (in_uv && $0 ~ /^[ \t]*\[/) { print_missing(); in_uv=0 } }
		{ if (in_uv && $0 ~ /^[ \t]*no-index[ \t]*=/) { print "no-index = true"; saw_no=1; next } }
		{ if (in_uv && $0 ~ /^[ \t]*find-links[ \t]*=/) { print "find-links = [\"./wheels\"]"; saw_find=1; next } }
		{ if (in_uv && $0 ~ /^[ \t]*prerelease[ \t]*=/) { print "prerelease = \"allow\""; saw_pre=1; next } }
		{ print }
		END {
			if (in_uv) { print_missing() }
			if (!saw_uv) {
				print ""
				print "[tool.uv]"
				print "no-index = true"
				print "find-links = [\"./wheels\"]"
				print "prerelease = \"allow\""
			}
		}
		' "$PYFILE" > "$PYFILE.tmp" && mv "$PYFILE.tmp" "$PYFILE"
		echo "Injected [tool.uv] into $PYFILE"
	}

	if python3 -m pip --version &> /dev/null 2>&1; then
		PIP_CMD="python3 -m pip"
	elif command -v pip &> /dev/null && pip --version &> /dev/null 2>&1; then
		PIP_CMD=pip
	elif command -v pip3 &> /dev/null && pip3 --version &> /dev/null 2>&1; then
		PIP_CMD=pip3
	else
		echo "pip not found. Install: python3 -m ensurepip --upgrade"
		exit 1
	fi
	echo "✓ Using pip: ${PIP_CMD}"

	# ============================================
	# Step 1: Detect Python and platform configuration
	# ============================================
	echo ""
	echo "=========================================="
	echo "Step 1: Detecting Python and platform"
	echo "=========================================="

	# Detect Python version
	PYTHON_CMD_FOR_UV="python3"
	PY_VERSION_FULL=$(python3 --version 2>&1 | awk '{print $2}')
	PY_MAJOR=$(echo $PY_VERSION_FULL | cut -d. -f1)
	PY_MINOR=$(echo $PY_VERSION_FULL | cut -d. -f2)
	PYTHON_VERSION=$PY_VERSION_FULL

	echo "Detected Python: $PYTHON_VERSION"

	# If Python is 3.14+, try to use 3.12 or 3.13 for better compatibility
	if [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -ge 14 ]; then
		echo "⚠ Warning: Python $PYTHON_VERSION is too new for some packages"
		if command -v python3.12 &> /dev/null; then
			PYTHON_CMD_FOR_UV="python3.12"
			PYTHON_VERSION=$($PYTHON_CMD_FOR_UV --version 2>&1 | awk '{print $2}')
			echo "✓ Switched to python3.12 ($PYTHON_VERSION) for better compatibility"
		elif command -v python3.13 &> /dev/null; then
			PYTHON_CMD_FOR_UV="python3.13"
			PYTHON_VERSION=$($PYTHON_CMD_FOR_UV --version 2>&1 | awk '{print $2}')
			echo "✓ Switched to python3.13 ($PYTHON_VERSION) for better compatibility"
		else
			echo "⚠ Warning: No compatible Python version found, proceeding with $PYTHON_VERSION"
		fi
	else
		echo "✓ Python version $PYTHON_VERSION is compatible"
	fi

	# Extract Python major.minor for uv
	UV_PY_VERSION=$($PYTHON_CMD_FOR_UV - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)

	# Determine uv target platform to avoid cross-platform dependency conflicts
	local UV_PLATFORM=""
	if [[ -n "$RAW_PLATFORM" ]]; then
		case "$RAW_PLATFORM" in
			*linux*|*manylinux* )
				UV_PLATFORM="linux"
				echo "Target platform: Linux (cross-compilation from $OS_TYPE)"
				;;
			*macos*|*darwin* )
				UV_PLATFORM="macos"
				echo "Target platform: macOS (cross-compilation from $OS_TYPE)"
				;;
			*win* )
				UV_PLATFORM="windows"
				echo "Target platform: Windows (cross-compilation from $OS_TYPE)"
				;;
			* )
				UV_PLATFORM=""
				echo "Target platform: current ($OS_TYPE)"
				;;
		esac
	else
		if [[ "$OS_TYPE" == "darwin" ]]; then
			UV_PLATFORM="macos"
		elif [[ "$OS_TYPE" == "linux" ]]; then
			UV_PLATFORM="linux"
		elif [[ "$OS_TYPE" == "windows" ]]; then
			UV_PLATFORM="windows"
		fi
		echo "Target platform: $UV_PLATFORM (current system)"
	fi

	# Set prerelease flag
	UV_PRERELEASE_FLAG=""
	if [[ "$PRERELEASE_ALLOW" -eq 1 ]]; then
		UV_PRERELEASE_FLAG="--prerelease=allow"
		echo "Prerelease versions: allowed"
	else
		echo "Prerelease versions: disallowed"
	fi

	echo "✓ Configuration: platform=${UV_PLATFORM:-current}, python=$UV_PY_VERSION"

	# ============================================
	# Step 2: Generate requirements.txt from pyproject.toml
	# ============================================
	echo ""
	echo "=========================================="
	echo "Step 2: Processing dependencies"
	echo "=========================================="

	# Always derive requirements.txt from pyproject.toml when uv is available.
	# Shipped requirements.txt files are often incomplete — they may omit transitive
	# deps of framework packages (e.g. dify-plugin → socksio) that the plugin author
	# expected the Dify runtime to supply.  uv export resolves the full closure.
	if [ -f "pyproject.toml" ] && command -v uv &> /dev/null; then
		# Always run uv lock even if uv.lock already exists.
		# Plugins built in a Dify dev environment often ship an incomplete uv.lock that
		# omits transitive deps of pre-installed packages (e.g. dify-plugin → socksio).
		# uv lock updates the lock file incrementally: existing pinned versions are kept,
		# but missing transitive deps are resolved and added.
		echo "Resolving/updating uv.lock..."
		uv lock --python "${UV_PY_VERSION}" ${UV_PRERELEASE_FLAG}
		if [[ $? -ne 0 ]]; then
			echo "✗ Error: uv lock failed"
			exit 1
		fi
		echo "✓ uv.lock resolved successfully"

		echo "Exporting complete requirements.txt from uv.lock (all transitive deps, no dev)..."
		uv export --format requirements-txt --no-hashes --no-dev \
			--python "${UV_PY_VERSION}" ${UV_PRERELEASE_FLAG} \
			-o requirements.txt
		if [[ $? -ne 0 ]]; then
			echo "✗ Error: uv export failed"
			exit 1
		fi
		echo "✓ requirements.txt generated successfully"
	elif [ -f "requirements.txt" ]; then
		echo "✓ Using existing requirements.txt (uv unavailable; transitive deps may be incomplete)"
	elif [ -f "pyproject.toml" ]; then
		echo "✗ Error: pyproject.toml found but uv is not installed and no requirements.txt exists"
		echo "  Please install uv: pip install uv"
		exit 1
	fi

	[ ! -f "requirements.txt" ] && echo "✗ Error: requirements.txt not found" && exit 1

	# ============================================
	# Step 3: Download Python dependencies as wheels
	# ============================================
	echo ""
	echo "=========================================="
	echo "Step 3: Downloading dependencies"
	echo "=========================================="
	echo "Index URL: ${PIP_MIRROR_URL}"
	[ -n "$PIP_PLATFORM" ] && echo "Platform: ${RAW_PLATFORM}"

	# pip two-pass download helper (used when uv is unavailable):
	# pass 1 — binary wheels for the target platform (--only-binary required by pip for --platform)
	# pass 2 — --no-deps without platform constraint, picks up sdist-only pure-Python packages
	#           --no-deps is safe because uv export already lists all transitive deps explicitly;
	#           it also satisfies pip's rule that requires --no-deps OR --only-binary when
	#           platform/interpreter constraints are present in the requirements file
	pip_download_with_fallback() {
		local status=0
		${PIP_CMD} download ${PIP_PLATFORM} --prefer-binary -r requirements.txt -d ./wheels \
			--index-url ${PIP_MIRROR_URL} --trusted-host mirrors.aliyun.com || status=$?
		if [[ $status -ne 0 ]] && [[ -n "$PIP_PLATFORM" ]]; then
			echo "⚠ Binary-only pass incomplete; retrying with --no-deps for sdist-only packages..."
			${PIP_CMD} download --no-deps --prefer-binary -r requirements.txt -d ./wheels \
				--index-url ${PIP_MIRROR_URL} --trusted-host mirrors.aliyun.com
			return $?
		fi
		return $status
	}

	mkdir -p ./wheels
	echo "Downloading wheels to ./wheels/..."
	if command -v uv &> /dev/null && uv pip download --help &> /dev/null 2>&1; then
		echo "Using uv pip download for consistent resolver..."
		UV_DL_STATUS=0
		uv pip download \
			-r requirements.txt \
			-o ./wheels \
			${RAW_PLATFORM:+--python-platform ${RAW_PLATFORM}} \
			--python "${UV_PY_VERSION}" \
			${UV_PRERELEASE_FLAG} \
			--index-url "${PIP_MIRROR_URL}" || UV_DL_STATUS=$?
		# If cross-platform download failed, retry without --python-platform to pick up
		# sdist-only pure-Python packages that have no platform-specific wheel
		if [[ $UV_DL_STATUS -ne 0 ]] && [[ -n "$RAW_PLATFORM" ]]; then
			echo "⚠ Cross-platform uv download incomplete; retrying without --python-platform for sdist-only packages..."
			uv pip download \
				-r requirements.txt \
				-o ./wheels \
				--python "${UV_PY_VERSION}" \
				${UV_PRERELEASE_FLAG} \
				--index-url "${PIP_MIRROR_URL}" || UV_DL_STATUS=$?
		fi
		if [[ $UV_DL_STATUS -ne 0 ]]; then
			echo "✗ Error: uv pip download failed"
			exit 1
		fi
	else
		pip_download_with_fallback
		if [[ $? -ne 0 ]]; then
			echo "✗ Error: Failed to download dependencies"
			exit 1
		fi
	fi

	# Count downloaded wheels
	WHEEL_COUNT=$(ls -1 ./wheels/*.whl 2>/dev/null | wc -l)
	echo "✓ Downloaded $WHEEL_COUNT wheel packages"

	# ============================================
	# Step 4: Configure offline mode
	# ============================================
	echo ""
	echo "=========================================="
	echo "Step 4: Configuring offline mode"
	echo "=========================================="

	# Inject [tool.uv] offline config into pyproject.toml AFTER wheels are downloaded
	if [ -f "pyproject.toml" ]; then
		echo "Injecting [tool.uv] offline configuration into pyproject.toml..."
		inject_uv_into_pyproject "pyproject.toml"
	fi

	# uv.lock is intentionally NOT regenerated here.
	# The wheels downloaded in Step 3 come from the same PyPI index that produced the
	# original uv.lock, so their hashes are already consistent.  The [tool.uv] injection
	# above (no-index + find-links) is all that is needed for Dify's "uv sync" to resolve
	# packages from ./wheels/ at runtime.  Re-running "uv lock" offline would fail for
	# plugins that declare dev dependencies (e.g. black, pytest) because those are
	# intentionally excluded from ./wheels/ as they are not needed at runtime.

	# Also patch requirements.txt for pip-based fallback installation
	echo "Updating requirements.txt for offline installation..."
	if [[ "linux" == "$OS_TYPE" ]]; then
		sed -i '1i\--no-index --find-links=./wheels/' requirements.txt
		[ -f ".difyignore" ] && IGNORE_PATH=.difyignore || IGNORE_PATH=.gitignore
		[ -f "$IGNORE_PATH" ] && sed -i '/^wheels\//d' "${IGNORE_PATH}"
	elif [[ "darwin" == "$OS_TYPE" ]]; then
		sed -i ".bak" '1i\--no-index --find-links=./wheels/' requirements.txt && rm -f requirements.txt.bak
		[ -f ".difyignore" ] && IGNORE_PATH=.difyignore || IGNORE_PATH=.gitignore
		[ -f "$IGNORE_PATH" ] && sed -i ".bak" '/^wheels\//d' "${IGNORE_PATH}" && rm -f "${IGNORE_PATH}.bak"
	fi
	echo "✓ requirements.txt updated for offline mode"

	# ============================================
	# Step 5: Package the plugin
	# ============================================
	echo ""
	echo "=========================================="
	echo "Step 5: Packaging plugin"
	echo "=========================================="

	cd ${CURR_DIR} || exit 1
	chmod 755 ${CURR_DIR}/${CMD_NAME}

	OUTPUT_PACKAGE="${CURR_DIR}/${PACKAGE_NAME}-${PACKAGE_SUFFIX}.difypkg"
	echo "Packaging: ${PACKAGE_NAME}"
	echo "Output: ${OUTPUT_PACKAGE}"
	echo "Max size: 5120 MB"

	${CURR_DIR}/${CMD_NAME} plugin package ${CURR_DIR}/${PACKAGE_NAME} \
		-o ${OUTPUT_PACKAGE} --max-size 5120
	if [[ $? -ne 0 ]]; then
		echo "✗ Error: Packaging failed"
		exit 1
	fi

	# Get file size
	FILE_SIZE=$(du -h "${OUTPUT_PACKAGE}" | cut -f1)
	echo ""
	echo "=========================================="
	echo "✓ Package created successfully!"
	echo "=========================================="
	echo "Location: ${OUTPUT_PACKAGE}"
	echo "Size: ${FILE_SIZE}"
	echo "Platform: ${RAW_PLATFORM:-current}"
}

install_unzip(){
	if ! command -v unzip &> /dev/null; then
		echo "Installing unzip ..."
		yum -y install unzip
		if [ $? -ne 0 ]; then
			echo "Install unzip failed."
			exit 1
		fi
	fi
}

print_usage() {
	echo "usage: $0 [-p platform] [-s package_suffix] [-R] {market|github|local}"
	echo "-p platform: python packages' platform. Using for crossing repacking.
        For example: -p manylinux2014_x86_64 or -p manylinux2014_aarch64"
	echo "-s package_suffix: The suffix name of the output offline package.
        For example: -s linux-amd64 or -s linux-arm64"
	echo "-R: allow pre-release versions during uv resolution (maps to --prerelease=allow)"
	exit 1
}

while getopts "p:s:R" opt; do
	case "$opt" in
		p) RAW_PLATFORM="${OPTARG}"; PIP_PLATFORM="--platform ${OPTARG} --only-binary=:all:" ;;
		s) PACKAGE_SUFFIX="${OPTARG}" ;;
		R) PRERELEASE_ALLOW=1 ;;
		*) print_usage; exit 1 ;;
	esac
done

shift $((OPTIND - 1))

echo "$1"
case "$1" in
	'market')
	market $@
	;;
	'github')
	github $@
	;;
	'local')
	_local $@
	;;
	*)

print_usage
exit 1
esac
exit 0
