#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE=""
SKIP_VSCODE=0
DRY_RUN=0
DRY_RUN_SET_BY_CLI=0

# Feature flags (defaults; can be overridden by YAML config).
ENABLE_APT_UPGRADE=1
ENABLE_BASE_PACKAGES=1
ENABLE_TROUBLESHOOTING_UTILS=1
ENABLE_AWS_CLI=1
ENABLE_AZURE_CLI=1
ENABLE_GCLOUD_CLI=1
ENABLE_TERRAFORM=1
ENABLE_TFENV=1
ENABLE_DOTNET=1
ENABLE_GO=1
ENABLE_NODE=1
ENABLE_GITHUB_CLI=1
ENABLE_PYTHON=1
ENABLE_SHELL_QUALITY=1
ENABLE_DOCKER=1
ENABLE_TERRAFORM_QUALITY=1
ENABLE_GO_QUALITY=1
ENABLE_KUBERNETES=1
ENABLE_JAVA=0
ENABLE_FLUTTER=0
ENABLE_ANDROID_SDK=0
ENABLE_LOCALSTACK_TOOLING=0
ENABLE_OH_MY_ZSH=1
ENABLE_POWERLEVEL10K=1
ENABLE_ZSH_PLUGINS=1
ENABLE_SHELL_CONFIG=1
ENABLE_GIT_PROFILE_SCAFFOLD=1
ENABLE_VSCODE_SETUP=1

# Tool versions (pin for reproducible installs; "latest" fetches newest at run time).
GO_VERSION="latest"
NODE_CHANNEL="lts"
DOTNET_SDK_VERSION="8.0"
NVM_VERSION="v0.40.3"
TERRAFORM_VERSION="latest"
TERRAFORM_DOCS_VERSION="v0.19.0"
K9S_VERSION="latest"
SHFMT_VERSION="v3.10.0"
YQ_VERSION="latest"
FLUTTER_CHANNEL="stable"
JDK_VERSION="17"
# Android SDK pins (from the real mobile apps' build.gradle: compileSdk 35, ndk 27.0.12077973).
ANDROID_API_LEVEL="35"
ANDROID_BUILD_TOOLS="35.0.0"
ANDROID_NDK_VERSION="27.0.12077973"
ANDROID_CMDLINE_TOOLS_VERSION="11076708"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --skip-vscode)
      SKIP_VSCODE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      DRY_RUN_SET_BY_CLI=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--config <path>] [--skip-vscode] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

log() {
  printf '\n==> %s\n' "$1"
}

yaml_get_value() {
  local file="$1"
  local key="$2"
  local default_value="$3"

  if [[ ! -f "$file" ]]; then
    printf '%s\n' "$default_value"
    return
  fi

  local value
  value="$(awk -v k="$key" '
    {
      line=$0
      sub(/#.*/, "", line)
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (line == "") next
      idx=index(line, ":")
      if (idx == 0) next
      key_part=substr(line, 1, idx-1)
      val_part=substr(line, idx+1)
      gsub(/^[ \t]+|[ \t]+$/, "", key_part)
      gsub(/^[ \t]+|[ \t]+$/, "", val_part)
      first=substr(val_part, 1, 1)
      last=substr(val_part, length(val_part), 1)
      if (length(val_part) >= 2 && ((first == "\"" && last == "\"") || (first == "\047" && last == "\047"))) {
        val_part = substr(val_part, 2, length(val_part) - 2)
      }
      if (key_part == k) {
        print val_part
      }
    }
  ' "$file" | tail -n1)"

  if [[ -z "$value" ]]; then
    printf '%s\n' "$default_value"
  else
    printf '%s\n' "$value"
  fi
}

yaml_get_bool() {
  local file="$1"
  local key="$2"
  local default_value="$3"
  local raw

  raw="$(yaml_get_value "$file" "$key" "$default_value")"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"

  case "$raw" in
    true | yes | 1) printf '1\n' ;;
    false | no | 0) printf '0\n' ;;
    *) printf '%s\n' "$default_value" ;;
  esac
}

print_bool() {
  local value="$1"
  if [[ "$value" -eq 1 ]]; then
    printf 'enabled\n'
  else
    printf 'disabled\n'
  fi
}

print_dry_run_plan() {
  log "Dry-run mode is enabled"
  echo "No changes will be applied."
  echo "Config file: ${CONFIG_FILE}"
  echo
  echo "Planned actions from feature flags:"
  echo "- apt upgrade: $(print_bool "$ENABLE_APT_UPGRADE")"
  echo "- base packages install: $(print_bool "$ENABLE_BASE_PACKAGES")"
  echo "- troubleshooting utilities install: $(print_bool "$ENABLE_TROUBLESHOOTING_UTILS")"
  echo "- AWS CLI install: $(print_bool "$ENABLE_AWS_CLI")"
  echo "- Azure CLI install: $(print_bool "$ENABLE_AZURE_CLI")"
  echo "- Google Cloud CLI install: $(print_bool "$ENABLE_GCLOUD_CLI")"
  echo "- Terraform install: $(print_bool "$ENABLE_TERRAFORM")"
  echo "- tfenv install: $(print_bool "$ENABLE_TFENV")"
  echo "- .NET SDK install: $(print_bool "$ENABLE_DOTNET")"
  echo "- Go install: $(print_bool "$ENABLE_GO")"
  echo "- Node.js via nvm install: $(print_bool "$ENABLE_NODE")"
  echo "- GitHub CLI (gh) install: $(print_bool "$ENABLE_GITHUB_CLI")"
  echo "- Python 3 + pipx install: $(print_bool "$ENABLE_PYTHON")"
  echo "- shell quality (shellcheck, shfmt, bats, yq) install: $(print_bool "$ENABLE_SHELL_QUALITY")"
  echo "- Docker Engine + Compose + Buildx install: $(print_bool "$ENABLE_DOCKER")"
  echo "- Terraform quality (tflint, terraform-docs, trivy, pre-commit, gitlint) install: $(print_bool "$ENABLE_TERRAFORM_QUALITY")"
  echo "- Go quality (golangci-lint, govulncheck, gosec, staticcheck, air) install: $(print_bool "$ENABLE_GO_QUALITY")"
  echo "- Kubernetes tools (kubectl, helm, k9s) install: $(print_bool "$ENABLE_KUBERNETES")"
  echo "- Java (OpenJDK ${JDK_VERSION}) install: $(print_bool "$ENABLE_JAVA")"
  echo "- Flutter SDK (${FLUTTER_CHANNEL}, ~/flutter) install: $(print_bool "$ENABLE_FLUTTER")"
  echo "- Android SDK (platform-tools, platforms;android-${ANDROID_API_LEVEL}, build-tools, ndk) install: $(print_bool "$ENABLE_ANDROID_SDK")"
  echo "- LocalStack tooling (localstack, awslocal) install: $(print_bool "$ENABLE_LOCALSTACK_TOOLING")"
  echo "- Oh My Zsh install: $(print_bool "$ENABLE_OH_MY_ZSH")"
  echo "- Powerlevel10k install: $(print_bool "$ENABLE_POWERLEVEL10K")"
  echo "- zsh plugins install: $(print_bool "$ENABLE_ZSH_PLUGINS")"
  echo "- shell file configuration: $(print_bool "$ENABLE_SHELL_CONFIG")"
  echo "- git profile scaffolding: $(print_bool "$ENABLE_GIT_PROFILE_SCAFFOLD")"
  echo "- VS Code WSL configuration: $(print_bool "$ENABLE_VSCODE_SETUP")"
  echo
  echo "Pinned tool versions:"
  echo "- Go: ${GO_VERSION}"
  echo "- Node channel: ${NODE_CHANNEL}"
  echo "- .NET SDK: ${DOTNET_SDK_VERSION}"
  echo "- nvm: ${NVM_VERSION}"
  echo "- Terraform (tfenv): ${TERRAFORM_VERSION}"
  echo "- terraform-docs: ${TERRAFORM_DOCS_VERSION}"
  echo "- k9s: ${K9S_VERSION}"
  echo "- shfmt: ${SHFMT_VERSION}"
  echo "- yq: ${YQ_VERSION}"
  echo "- Flutter channel: ${FLUTTER_CHANNEL}"
  echo "- OpenJDK: ${JDK_VERSION}"
  echo "- Android API level: ${ANDROID_API_LEVEL} (build-tools ${ANDROID_BUILD_TOOLS}, ndk ${ANDROID_NDK_VERSION})"
}

append_if_missing() {
  local file="$1"
  local line="$2"
  touch "$file"
  if ! grep -Fqx "$line" "$file"; then
    printf '%s\n' "$line" >>"$file"
  fi
}

backup_file_once() {
  local file="$1"
  if [[ -f "$file" && ! -f "${file}.onboarding.bak" ]]; then
    cp "$file" "${file}.onboarding.bak"
  fi
}

merge_zsh_plugins() {
  local zshrc="$1"
  shift
  local -a required=("$@")
  local -a current=()
  local existing
  local plugin

  if grep -Eq '^plugins=\(.*\)[[:space:]]*$' "$zshrc"; then
    existing="$(sed -nE 's|^plugins=\((.*)\)[[:space:]]*$|\1|p' "$zshrc" | head -n1)"
    # shellcheck disable=SC2206
    current=(${existing})
    for plugin in "${required[@]}"; do
      if [[ " ${current[*]} " != *" ${plugin} "* ]]; then
        current+=("$plugin")
      fi
    done
    sed -i -E "s|^plugins=\(.*\)[[:space:]]*\$|plugins=(${current[*]})|" "$zshrc"
  else
    printf '\nplugins=(%s)\n' "${required[*]}" >>"$zshrc"
  fi
}

configure_git_profiles() {
  local gitconfig
  local work_profile
  local personal_profile

  gitconfig="${HOME}/.gitconfig"
  work_profile="${HOME}/.gitconfig-work"
  personal_profile="${HOME}/.gitconfig-personal"

  if [[ ! -f "${gitconfig}" ]]; then
    cat <<'EOF' >"${gitconfig}"
[init]
  defaultBranch = main

[pull]
  rebase = false

[url "https://github.com/"]
  insteadOf = git@github.com:
  insteadOf = ssh://git@github.com/

[includeIf "gitdir:~/repos/"]
  path = ~/.gitconfig-work

[includeIf "gitdir:~/github/"]
  path = ~/.gitconfig-personal
EOF
  fi

  if [[ ! -f "${work_profile}" ]]; then
    cat <<'EOF' >"${work_profile}"
[user]
  name = Your Work Name
  email = your.name@company.com
EOF
  fi

  if [[ ! -f "${personal_profile}" ]]; then
    cat <<'EOF' >"${personal_profile}"
[user]
  name = Your Personal Name
  email = you@example.com
EOF
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command missing: $cmd" >&2
    exit 1
  fi
}

install_aws_cli() {
  local arch
  local aws_arch
  local tmp_dir
  local aws_zip
  local aws_src

  arch="$(uname -m)"
  case "${arch}" in
    x86_64) aws_arch="x86_64" ;;
    aarch64 | arm64) aws_arch="aarch64" ;;
    *)
      echo "Unsupported architecture for AWS CLI install: ${arch}" >&2
      exit 1
      ;;
  esac

  tmp_dir="$(mktemp -d)"
  aws_zip="${tmp_dir}/awscliv2.zip"
  aws_src="${tmp_dir}/aws-src"
  mkdir -p "${aws_src}"

  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "${aws_zip}"
  unzip -q "${aws_zip}" -d "${aws_src}"
  ${SUDO} "${aws_src}/aws/install" --update
  rm -rf "${tmp_dir}"

  aws --version
}

install_azure_cli() {
  ${SUDO} mkdir -p /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg

  local az_repo
  az_repo="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main"
  echo "${az_repo}" | ${SUDO} tee /etc/apt/sources.list.d/azure-cli.list >/dev/null

  ${SUDO} apt-get update -y
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y azure-cli

  az version --output table || true
}

install_gcloud_cli() {
  ${SUDO} mkdir -p /usr/share/keyrings
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | ${SUDO} gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | ${SUDO} tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null

  ${SUDO} apt-get update -y
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y google-cloud-cli

  gcloud --version | head -n 1
}

install_terraform_and_tfenv() {
  local distro_codename

  curl -fsSL https://apt.releases.hashicorp.com/gpg | ${SUDO} gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  distro_codename="$(lsb_release -cs)"
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${distro_codename} main" | ${SUDO} tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

  ${SUDO} apt-get update -y
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y terraform
  terraform -version | head -n 1

  if [[ "$ENABLE_TFENV" -ne 1 ]]; then
    return
  fi

  if [[ ! -d "${HOME}/.tfenv" ]]; then
    git clone --depth=1 https://github.com/tfutils/tfenv.git "${HOME}/.tfenv"
  else
    echo "tfenv already installed."
  fi

  export PATH="${HOME}/.tfenv/bin:${PATH}"
  if command -v tfenv >/dev/null 2>&1; then
    tfenv install "${TERRAFORM_VERSION}" || true
    tfenv use "${TERRAFORM_VERSION}" || true
  fi
}

install_dotnet_sdk() {
  local tmp_dir
  local pkg
  local os_id
  local os_version

  if command -v dotnet >/dev/null 2>&1; then
    echo "dotnet already installed: $(dotnet --version)"
    return
  fi

  os_id="$(grep -E '^ID=' /etc/os-release 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '"' || true)"
  os_version="$(grep -E '^VERSION_ID=' /etc/os-release 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '"' || true)"

  if [[ "${os_id}" != "ubuntu" ]]; then
    echo "Skipping .NET SDK: Microsoft package repo supports Ubuntu only (detected '${os_id:-unknown}')." >&2
    return
  fi

  tmp_dir="$(mktemp -d)"
  pkg="${tmp_dir}/packages-microsoft-prod.deb"

  wget -q "https://packages.microsoft.com/config/ubuntu/${os_version}/packages-microsoft-prod.deb" -O "${pkg}"
  ${SUDO} dpkg -i "${pkg}"
  rm -rf "${tmp_dir}"

  ${SUDO} apt-get update -y
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y "dotnet-sdk-${DOTNET_SDK_VERSION}"

  dotnet --version
}

install_go_sdk() {
  local arch
  local go_arch
  local go_version
  local tmp_dir
  local tar_file

  arch="$(uname -m)"
  case "${arch}" in
    x86_64) go_arch="amd64" ;;
    aarch64 | arm64) go_arch="arm64" ;;
    *)
      echo "Unsupported architecture for Go install: ${arch}" >&2
      exit 1
      ;;
  esac

  go_version=""
  if [[ "${GO_VERSION}" == "latest" ]]; then
    go_version="$(curl -fsSL https://go.dev/VERSION?m=text | head -n 1)"
  else
    go_version="go${GO_VERSION#go}"
  fi
  tmp_dir="$(mktemp -d)"
  tar_file="${tmp_dir}/${go_version}.linux-${go_arch}.tar.gz"

  curl -fsSL "https://go.dev/dl/${go_version}.linux-${go_arch}.tar.gz" -o "${tar_file}"
  ${SUDO} rm -rf /usr/local/go
  ${SUDO} tar -C /usr/local -xzf "${tar_file}"
  rm -rf "${tmp_dir}"

  export PATH="/usr/local/go/bin:${PATH}"
  /usr/local/go/bin/go version
}

install_nvm_node() {
  export NVM_DIR="${HOME}/.nvm"
  if [[ ! -d "${NVM_DIR}" ]]; then
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
  fi

  # shellcheck disable=SC1090
  if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    . "${NVM_DIR}/nvm.sh"
    if [[ "${NODE_CHANNEL}" == "lts" ]]; then
      nvm install --lts
      nvm alias default 'lts/*'
    else
      nvm install "${NODE_CHANNEL}"
      nvm alias default "${NODE_CHANNEL}"
    fi
    if command -v corepack >/dev/null 2>&1; then
      corepack enable || true
      corepack prepare pnpm@latest --activate || true
      corepack prepare yarn@stable --activate || true
    fi
    node --version
    npm --version
  fi
}

LOCAL_BIN="${HOME}/.local/bin"

go_arch() {
  case "$(uname -m)" in
    x86_64) printf 'amd64\n' ;;
    aarch64 | arm64) printf 'arm64\n' ;;
    *) printf 'unsupported\n' ;;
  esac
}

# Download a raw binary to LOCAL_BIN (best effort; never aborts the run).
install_raw_bin() {
  local url="$1"
  local name="$2"
  mkdir -p "${LOCAL_BIN}"
  if curl -fsSL "$url" -o "${LOCAL_BIN}/${name}"; then
    chmod +x "${LOCAL_BIN}/${name}"
    echo "Installed ${name} to ${LOCAL_BIN}"
  else
    echo "Download failed for ${name}: ${url}" >&2
  fi
}

# Extract a single binary from a .tar.gz release into LOCAL_BIN (best effort).
install_targz_bin() {
  local url="$1"
  local name="$2"
  local tmp
  tmp="$(mktemp -d)"
  if curl -fsSL "$url" -o "${tmp}/archive.tgz" && tar -C "${tmp}" -xzf "${tmp}/archive.tgz"; then
    local found
    found="$(find "${tmp}" -type f -name "${name}" | head -n1)"
    mkdir -p "${LOCAL_BIN}"
    if [[ -n "$found" ]]; then
      install -m 0755 "$found" "${LOCAL_BIN}/${name}"
      echo "Installed ${name} to ${LOCAL_BIN}"
    else
      echo "Binary '${name}' not found inside ${url}" >&2
    fi
  else
    echo "Download/extract failed for ${name}: ${url}" >&2
  fi
  rm -rf "${tmp}"
}

# Extract a single binary from a .zip release into LOCAL_BIN (best effort).
install_zip_bin() {
  local url="$1"
  local name="$2"
  local tmp
  tmp="$(mktemp -d)"
  if curl -fsSL "$url" -o "${tmp}/archive.zip" && unzip -qo "${tmp}/archive.zip" -d "${tmp}"; then
    local found
    found="$(find "${tmp}" -type f -name "${name}" | head -n1)"
    mkdir -p "${LOCAL_BIN}"
    if [[ -n "$found" ]]; then
      install -m 0755 "$found" "${LOCAL_BIN}/${name}"
      echo "Installed ${name} to ${LOCAL_BIN}"
    else
      echo "Binary '${name}' not found inside ${url}" >&2
    fi
  else
    echo "Download/unzip failed for ${name}: ${url}" >&2
  fi
  rm -rf "${tmp}"
}

# Idempotent `go install` into ${HOME}/go/bin.
go_install() {
  local pkg="$1"
  local bin="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "Already installed (go): $bin"
    return
  fi
  if command -v go >/dev/null 2>&1; then
    GOBIN="${HOME}/go/bin" go install "$pkg" || echo "go install failed for ${pkg}" >&2
  else
    echo "Skipping 'go install ${pkg}': go is not on PATH (enable install_go)." >&2
  fi
}

# Idempotent pipx install.
pipx_install() {
  local pkg="$1"
  local bin="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "Already installed (pipx): $bin"
    return
  fi
  if command -v pipx >/dev/null 2>&1; then
    pipx install "$pkg" || echo "pipx install failed for ${pkg}" >&2
  else
    echo "Skipping pipx install of ${pkg}: pipx unavailable (enable install_python)." >&2
  fi
}

install_github_cli() {
  if command -v gh >/dev/null 2>&1; then
    echo "gh already installed: $(gh --version | head -n1)"
    return
  fi
  ${SUDO} mkdir -p /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  ${SUDO} chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | ${SUDO} tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  ${SUDO} apt-get update -y
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y gh
  gh --version | head -n1
}

install_python_tooling() {
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-venv
  if ! command -v pipx >/dev/null 2>&1; then
    ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y pipx ||
      python3 -m pip install --user --break-system-packages pipx ||
      python3 -m pip install --user pipx || true
  fi
  if command -v pipx >/dev/null 2>&1; then
    pipx ensurepath || true
  fi
  python3 --version
}

install_shell_quality() {
  local arch
  arch="$(go_arch)"
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y shellcheck bats
  if ! command -v shfmt >/dev/null 2>&1; then
    install_raw_bin "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_${arch}" shfmt
  fi
  if ! command -v yq >/dev/null 2>&1; then
    local yq_url
    if [[ "${YQ_VERSION}" == "latest" ]]; then
      yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}"
    else
      yq_url="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${arch}"
    fi
    install_raw_bin "$yq_url" yq
  fi
}

install_docker_engine() {
  if command -v docker >/dev/null 2>&1; then
    echo "docker already installed: $(docker --version)"
  else
    ${SUDO} install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    ${SUDO} chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | ${SUDO} tee /etc/apt/sources.list.d/docker.list >/dev/null
    ${SUDO} apt-get update -y
    ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  if getent group docker >/dev/null 2>&1; then
    ${SUDO} usermod -aG docker "$USER" || true
    echo "Added ${USER} to the docker group (log out/in for it to take effect)."
  fi
  echo "On WSL without Docker Desktop, start the daemon with: sudo service docker start"
  docker --version || true
}

install_terraform_quality() {
  local arch
  arch="$(go_arch)"
  if ! command -v tflint >/dev/null 2>&1; then
    install_zip_bin "https://github.com/terraform-linters/tflint/releases/latest/download/tflint_linux_${arch}.zip" tflint
  fi
  if ! command -v terraform-docs >/dev/null 2>&1; then
    install_targz_bin "https://terraform-docs.io/dl/${TERRAFORM_DOCS_VERSION}/terraform-docs-${TERRAFORM_DOCS_VERSION}-linux-${arch}.tar.gz" terraform-docs
  fi
  if ! command -v trivy >/dev/null 2>&1; then
    mkdir -p "${LOCAL_BIN}"
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b "${LOCAL_BIN}" || echo "trivy install failed" >&2
  fi
  pipx_install pre-commit pre-commit
  pipx_install gitlint gitlint
}

install_go_quality() {
  export PATH="/usr/local/go/bin:${HOME}/go/bin:${PATH}"
  if ! command -v golangci-lint >/dev/null 2>&1; then
    mkdir -p "${LOCAL_BIN}"
    curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh | sh -s -- -b "${LOCAL_BIN}" || echo "golangci-lint install failed" >&2
  fi
  go_install "golang.org/x/vuln/cmd/govulncheck@latest" govulncheck
  go_install "github.com/securego/gosec/v2/cmd/gosec@latest" gosec
  go_install "honnef.co/go/tools/cmd/staticcheck@latest" staticcheck
  go_install "github.com/air-verse/air@latest" air
  go_install "github.com/git-chglog/git-chglog/cmd/git-chglog@latest" git-chglog
}

install_kubernetes_tools() {
  local arch
  arch="$(go_arch)"
  if ! command -v kubectl >/dev/null 2>&1; then
    ${SUDO} mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    ${SUDO} chmod go+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | ${SUDO} tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
    ${SUDO} apt-get update -y
    ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y kubectl
  fi
  if ! command -v helm >/dev/null 2>&1; then
    curl -fsSL https://baltocdn.com/helm/signing.asc | ${SUDO} gpg --dearmor -o /usr/share/keyrings/helm.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | ${SUDO} tee /etc/apt/sources.list.d/helm-stable-debian.list >/dev/null
    ${SUDO} apt-get update -y
    ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y helm
  fi
  if ! command -v k9s >/dev/null 2>&1; then
    local url
    if [[ "${K9S_VERSION}" == "latest" ]]; then
      url="https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${arch}.tar.gz"
    else
      url="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${arch}.tar.gz"
    fi
    install_targz_bin "$url" k9s
  fi
}

install_java() {
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y "openjdk-${JDK_VERSION}-jdk"
  java -version 2>&1 | head -n1 || true
}

install_flutter_sdk() {
  local flutter_dir="${HOME}/flutter"
  # Linux desktop toolchain deps (clang/cmake/ninja/gtk are in base packages); add mesa GLU.
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y libglu1-mesa || true
  if [[ ! -d "${flutter_dir}" ]]; then
    git clone --depth 1 -b "${FLUTTER_CHANNEL}" https://github.com/flutter/flutter.git "${flutter_dir}"
  else
    echo "Flutter already present at ${flutter_dir}"
  fi
  export PATH="${flutter_dir}/bin:${PATH}"
  if command -v flutter >/dev/null 2>&1; then
    flutter config --no-analytics >/dev/null 2>&1 || true
    flutter config --enable-web >/dev/null 2>&1 || true
    flutter precache || true
    flutter --version || true
    echo "Flutter at ${flutter_dir}/bin (matches the apps' FLUTTER default)."
    echo "Enable Android builds with install_android_sdk. Android emulators belong on the host OS;"
    echo "in WSL you can build APKs and run 'flutter run -d chrome' (web)."
  fi
}

install_android_sdk() {
  # Ensure a JDK for sdkmanager (the apps target JDK 17).
  if ! command -v java >/dev/null 2>&1; then
    ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y "openjdk-${JDK_VERSION}-jdk"
  fi

  local android_home="${HOME}/Android/Sdk"
  local clt_dir="${android_home}/cmdline-tools/latest"
  export ANDROID_HOME="${android_home}"
  export ANDROID_SDK_ROOT="${android_home}"

  if [[ ! -x "${clt_dir}/bin/sdkmanager" ]]; then
    mkdir -p "${android_home}/cmdline-tools"
    local tmp
    tmp="$(mktemp -d)"
    if curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" -o "${tmp}/clt.zip" && unzip -qo "${tmp}/clt.zip" -d "${tmp}"; then
      rm -rf "${clt_dir}"
      mkdir -p "${clt_dir}"
      # The archive extracts a top-level 'cmdline-tools' dir; its contents go under latest/.
      if [[ -d "${tmp}/cmdline-tools" ]]; then
        mv "${tmp}/cmdline-tools/"* "${clt_dir}/"
      fi
    else
      echo "Android cmdline-tools download failed." >&2
    fi
    rm -rf "${tmp}"
  fi

  local sdkmanager="${clt_dir}/bin/sdkmanager"
  if [[ ! -x "${sdkmanager}" ]]; then
    echo "sdkmanager not available; skipping Android component install." >&2
    return 0
  fi

  local img_arch
  case "$(uname -m)" in
    aarch64 | arm64) img_arch="arm64-v8a" ;;
    *) img_arch="x86_64" ;;
  esac

  yes | "${sdkmanager}" --sdk_root="${android_home}" --licenses >/dev/null 2>&1 || true
  "${sdkmanager}" --sdk_root="${android_home}" \
    "platform-tools" "emulator" \
    "platforms;android-${ANDROID_API_LEVEL}" \
    "build-tools;${ANDROID_BUILD_TOOLS}" \
    "ndk;${ANDROID_NDK_VERSION}" \
    "system-images;android-${ANDROID_API_LEVEL};google_apis;${img_arch}" ||
    echo "Some Android SDK components failed to install; re-run to retry." >&2

  echo "Android SDK at ${android_home}. On WSL, build APKs here but run emulators on the Windows host."
}

install_localstack_tooling() {
  pipx_install localstack localstack
  pipx_install awscli-local awslocal
}

configure_vscode_wsl() {
  local settings_path
  local settings_dir
  local tmp_file
  local -a extensions
  local -a failed_extensions
  local ext

  if ! command -v code >/dev/null 2>&1; then
    echo "VS Code CLI 'code' was not found in this WSL shell."
    echo "Open this WSL distro in VS Code Remote and rerun this script, or run with --skip-vscode."
    return 0
  fi

  settings_path="${HOME}/.vscode-server/data/Machine/settings.json"
  settings_dir="$(dirname "${settings_path}")"
  mkdir -p "${settings_dir}"

  if [[ ! -f "${settings_path}" ]]; then
    printf '{}\n' >"${settings_path}"
  fi

  if ! jq empty "${settings_path}" >/dev/null 2>&1; then
    echo "VS Code settings file is not strict JSON. Remove comments/trailing commas or apply settings manually: ${settings_path}" >&2
    return 1
  fi

  tmp_file="$(mktemp)"
  jq '
    .["[terraform]"] = {
      "editor.defaultFormatter": "hashicorp.terraform",
      "editor.formatOnSave": true,
      "editor.tabSize": 2,
      "editor.insertSpaces": true
    } |
    .["[terraform-vars]"] = {
      "editor.defaultFormatter": "hashicorp.terraform",
      "editor.formatOnSave": true,
      "editor.tabSize": 2,
      "editor.insertSpaces": true
    } |
    .["terraform.languageServer.enable"] = true |
    .["terraform.validation.enableEnhancedValidation"] = true |
    .["files.associations"]["*.tf"] = "terraform" |
    .["files.associations"]["*.tfvars"] = "terraform-vars" |
    .["files.associations"]["*.tftest.hcl"] = "terraform" |
    .["terminal.integrated.defaultProfile.linux"] = "zsh" |
    .["terminal.integrated.fontFamily"] = "MesloLGS NF" |
    .["terminal.integrated.fontSize"] = 14 |
    .["terminal.integrated.scrollback"] = 10000 |
    .["editor.formatOnSave"] = true |
    .["files.trimTrailingWhitespace"] = true |
    .["files.insertFinalNewline"] = true |
    .["editor.renderWhitespace"] = "selection" |
    .["workbench.colorTheme"] = "Catppuccin Mocha"
  ' "${settings_path}" >"${tmp_file}"
  mv "${tmp_file}" "${settings_path}"

  local ext_file
  local line
  ext_file="${SCRIPT_DIR}/vscode-extensions.txt"
  extensions=()
  if [[ -f "${ext_file}" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(printf '%s' "$line" | tr -d '[:space:]')"
      [[ -z "$line" ]] && continue
      extensions+=("$line")
    done <"${ext_file}"
  else
    echo "Extension list not found: ${ext_file} (skipping extension install)." >&2
    return 0
  fi

  failed_extensions=()
  for ext in "${extensions[@]}"; do
    if code --install-extension "${ext}" --force; then
      echo "Installed VS Code extension: ${ext}"
    else
      failed_extensions+=("${ext}")
    fi
  done

  if [[ "${#failed_extensions[@]}" -gt 0 ]]; then
    echo "Some VS Code extensions failed to install:"
    printf '  - %s\n' "${failed_extensions[@]}"
    echo "Rerun this script later to retry extension installation."
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$CONFIG_FILE" ]]; then
  CONFIG_FILE="${SCRIPT_DIR}/setup-ubuntu-wsl.yaml"
fi

if [[ -f "$CONFIG_FILE" ]]; then
  log "Loading feature flags from ${CONFIG_FILE}"
  if [[ "$DRY_RUN_SET_BY_CLI" -ne 1 ]]; then
    DRY_RUN="$(yaml_get_bool "$CONFIG_FILE" "dry_run" "$DRY_RUN")"
  fi
  ENABLE_APT_UPGRADE="$(yaml_get_bool "$CONFIG_FILE" "apt_upgrade" "$ENABLE_APT_UPGRADE")"
  ENABLE_BASE_PACKAGES="$(yaml_get_bool "$CONFIG_FILE" "install_base_packages" "$ENABLE_BASE_PACKAGES")"
  ENABLE_TROUBLESHOOTING_UTILS="$(yaml_get_bool "$CONFIG_FILE" "install_troubleshooting_utils" "$ENABLE_TROUBLESHOOTING_UTILS")"
  ENABLE_AWS_CLI="$(yaml_get_bool "$CONFIG_FILE" "install_aws_cli" "$ENABLE_AWS_CLI")"
  ENABLE_AZURE_CLI="$(yaml_get_bool "$CONFIG_FILE" "install_azure_cli" "$ENABLE_AZURE_CLI")"
  ENABLE_GCLOUD_CLI="$(yaml_get_bool "$CONFIG_FILE" "install_gcloud_cli" "$ENABLE_GCLOUD_CLI")"
  ENABLE_TERRAFORM="$(yaml_get_bool "$CONFIG_FILE" "install_terraform" "$ENABLE_TERRAFORM")"
  ENABLE_TFENV="$(yaml_get_bool "$CONFIG_FILE" "install_tfenv" "$ENABLE_TFENV")"
  ENABLE_DOTNET="$(yaml_get_bool "$CONFIG_FILE" "install_dotnet" "$ENABLE_DOTNET")"
  ENABLE_GO="$(yaml_get_bool "$CONFIG_FILE" "install_go" "$ENABLE_GO")"
  ENABLE_NODE="$(yaml_get_bool "$CONFIG_FILE" "install_node" "$ENABLE_NODE")"
  ENABLE_OH_MY_ZSH="$(yaml_get_bool "$CONFIG_FILE" "install_oh_my_zsh" "$ENABLE_OH_MY_ZSH")"
  ENABLE_POWERLEVEL10K="$(yaml_get_bool "$CONFIG_FILE" "install_powerlevel10k" "$ENABLE_POWERLEVEL10K")"
  ENABLE_ZSH_PLUGINS="$(yaml_get_bool "$CONFIG_FILE" "install_zsh_plugins" "$ENABLE_ZSH_PLUGINS")"
  ENABLE_SHELL_CONFIG="$(yaml_get_bool "$CONFIG_FILE" "configure_shell_files" "$ENABLE_SHELL_CONFIG")"
  ENABLE_GIT_PROFILE_SCAFFOLD="$(yaml_get_bool "$CONFIG_FILE" "configure_git_profiles" "$ENABLE_GIT_PROFILE_SCAFFOLD")"
  ENABLE_VSCODE_SETUP="$(yaml_get_bool "$CONFIG_FILE" "configure_vscode_wsl" "$ENABLE_VSCODE_SETUP")"
  ENABLE_GITHUB_CLI="$(yaml_get_bool "$CONFIG_FILE" "install_github_cli" "$ENABLE_GITHUB_CLI")"
  ENABLE_PYTHON="$(yaml_get_bool "$CONFIG_FILE" "install_python" "$ENABLE_PYTHON")"
  ENABLE_SHELL_QUALITY="$(yaml_get_bool "$CONFIG_FILE" "install_shell_quality" "$ENABLE_SHELL_QUALITY")"
  ENABLE_DOCKER="$(yaml_get_bool "$CONFIG_FILE" "install_docker" "$ENABLE_DOCKER")"
  ENABLE_TERRAFORM_QUALITY="$(yaml_get_bool "$CONFIG_FILE" "install_terraform_quality" "$ENABLE_TERRAFORM_QUALITY")"
  ENABLE_GO_QUALITY="$(yaml_get_bool "$CONFIG_FILE" "install_go_quality" "$ENABLE_GO_QUALITY")"
  ENABLE_KUBERNETES="$(yaml_get_bool "$CONFIG_FILE" "install_kubernetes_tools" "$ENABLE_KUBERNETES")"
  ENABLE_JAVA="$(yaml_get_bool "$CONFIG_FILE" "install_java" "$ENABLE_JAVA")"
  ENABLE_FLUTTER="$(yaml_get_bool "$CONFIG_FILE" "install_flutter" "$ENABLE_FLUTTER")"
  ENABLE_ANDROID_SDK="$(yaml_get_bool "$CONFIG_FILE" "install_android_sdk" "$ENABLE_ANDROID_SDK")"
  ENABLE_LOCALSTACK_TOOLING="$(yaml_get_bool "$CONFIG_FILE" "install_localstack_tooling" "$ENABLE_LOCALSTACK_TOOLING")"
  GO_VERSION="$(yaml_get_value "$CONFIG_FILE" "go_version" "$GO_VERSION")"
  NODE_CHANNEL="$(yaml_get_value "$CONFIG_FILE" "node_channel" "$NODE_CHANNEL")"
  DOTNET_SDK_VERSION="$(yaml_get_value "$CONFIG_FILE" "dotnet_sdk_version" "$DOTNET_SDK_VERSION")"
  NVM_VERSION="$(yaml_get_value "$CONFIG_FILE" "nvm_version" "$NVM_VERSION")"
  TERRAFORM_VERSION="$(yaml_get_value "$CONFIG_FILE" "terraform_version" "$TERRAFORM_VERSION")"
  TERRAFORM_DOCS_VERSION="$(yaml_get_value "$CONFIG_FILE" "terraform_docs_version" "$TERRAFORM_DOCS_VERSION")"
  K9S_VERSION="$(yaml_get_value "$CONFIG_FILE" "k9s_version" "$K9S_VERSION")"
  SHFMT_VERSION="$(yaml_get_value "$CONFIG_FILE" "shfmt_version" "$SHFMT_VERSION")"
  YQ_VERSION="$(yaml_get_value "$CONFIG_FILE" "yq_version" "$YQ_VERSION")"
  FLUTTER_CHANNEL="$(yaml_get_value "$CONFIG_FILE" "flutter_channel" "$FLUTTER_CHANNEL")"
  JDK_VERSION="$(yaml_get_value "$CONFIG_FILE" "jdk_version" "$JDK_VERSION")"
  ANDROID_API_LEVEL="$(yaml_get_value "$CONFIG_FILE" "android_api_level" "$ANDROID_API_LEVEL")"
  ANDROID_BUILD_TOOLS="$(yaml_get_value "$CONFIG_FILE" "android_build_tools" "$ANDROID_BUILD_TOOLS")"
  ANDROID_NDK_VERSION="$(yaml_get_value "$CONFIG_FILE" "android_ndk_version" "$ANDROID_NDK_VERSION")"
  ANDROID_CMDLINE_TOOLS_VERSION="$(yaml_get_value "$CONFIG_FILE" "android_cmdline_tools_version" "$ANDROID_CMDLINE_TOOLS_VERSION")"
fi

if [[ "$SKIP_VSCODE" -eq 1 ]]; then
  ENABLE_VSCODE_SETUP=0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  print_dry_run_plan
  exit 0
fi

if [[ "${EUID}" -eq 0 ]]; then
  SUDO=""
else
  require_cmd sudo
  SUDO="sudo"
fi

BASE_APT_PACKAGES=(
  ca-certificates
  curl
  wget
  unzip
  zip
  jq
  git
  git-lfs
  rsync
  make
  build-essential
  software-properties-common
  apt-transport-https
  gnupg
  lsb-release
  xz-utils
  openssh-client
  clang
  cmake
  ninja-build
  pkg-config
  libgtk-3-dev
  liblzma-dev
  direnv
  zsh
)

TROUBLESHOOTING_APT_PACKAGES=(
  ripgrep
  fd-find
  traceroute
  tcptraceroute
  dnsutils
  net-tools
  iproute2
  iputils-ping
  mtr-tiny
  nmap
  tcpdump
  lsof
  strace
  whois
)

log "Updating apt metadata"
${SUDO} apt-get update -y

if [[ "$ENABLE_APT_UPGRADE" -eq 1 ]]; then
  log "Upgrading installed packages"
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
fi

if [[ "$ENABLE_BASE_PACKAGES" -eq 1 ]]; then
  log "Installing base packages"
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y "${BASE_APT_PACKAGES[@]}"
fi

if [[ "$ENABLE_TROUBLESHOOTING_UTILS" -eq 1 ]]; then
  log "Installing troubleshooting utilities"
  ${SUDO} DEBIAN_FRONTEND=noninteractive apt-get install -y "${TROUBLESHOOTING_APT_PACKAGES[@]}"
fi

if [[ "$ENABLE_AWS_CLI" -eq 1 ]]; then
  log "Installing AWS CLI v2"
  install_aws_cli
fi

if [[ "$ENABLE_AZURE_CLI" -eq 1 ]]; then
  log "Installing Azure CLI"
  install_azure_cli
fi

if [[ "$ENABLE_GCLOUD_CLI" -eq 1 ]]; then
  log "Installing Google Cloud CLI"
  install_gcloud_cli
fi

if [[ "$ENABLE_TERRAFORM" -eq 1 ]]; then
  log "Installing Terraform from HashiCorp repository"
  install_terraform_and_tfenv
elif [[ "$ENABLE_TFENV" -eq 1 ]]; then
  log "Skipping tfenv because install_terraform is disabled"
fi

if [[ "$ENABLE_DOTNET" -eq 1 ]]; then
  log "Installing .NET SDK for C#"
  install_dotnet_sdk
fi

if [[ "$ENABLE_GO" -eq 1 ]]; then
  log "Installing Go SDK"
  install_go_sdk
fi

if [[ "$ENABLE_NODE" -eq 1 ]]; then
  log "Installing NVM and Node.js toolchain"
  install_nvm_node
fi

# Ensure user-space install dirs are on PATH so re-run detection works this session.
mkdir -p "${LOCAL_BIN}" "${HOME}/go/bin"
export PATH="${LOCAL_BIN}:/usr/local/go/bin:${HOME}/go/bin:${PATH}"

if [[ "$ENABLE_GITHUB_CLI" -eq 1 ]]; then
  log "Installing GitHub CLI (gh)"
  install_github_cli
fi

if [[ "$ENABLE_PYTHON" -eq 1 ]]; then
  log "Installing Python 3 and pipx"
  install_python_tooling
fi

if [[ "$ENABLE_SHELL_QUALITY" -eq 1 ]]; then
  log "Installing shell quality tools (shellcheck, shfmt, bats, yq)"
  install_shell_quality
fi

if [[ "$ENABLE_DOCKER" -eq 1 ]]; then
  log "Installing Docker Engine, Compose, and Buildx"
  install_docker_engine
fi

if [[ "$ENABLE_TERRAFORM_QUALITY" -eq 1 ]]; then
  log "Installing Terraform quality tools (tflint, terraform-docs, trivy, pre-commit, gitlint)"
  install_terraform_quality
fi

if [[ "$ENABLE_GO_QUALITY" -eq 1 ]]; then
  log "Installing Go quality tools (golangci-lint, govulncheck, gosec, staticcheck, air)"
  install_go_quality
fi

if [[ "$ENABLE_KUBERNETES" -eq 1 ]]; then
  log "Installing Kubernetes tools (kubectl, helm, k9s)"
  install_kubernetes_tools
fi

if [[ "$ENABLE_JAVA" -eq 1 ]]; then
  log "Installing Java (OpenJDK ${JDK_VERSION})"
  install_java
fi

if [[ "$ENABLE_FLUTTER" -eq 1 ]]; then
  log "Installing Flutter SDK (${FLUTTER_CHANNEL})"
  install_flutter_sdk
fi

if [[ "$ENABLE_ANDROID_SDK" -eq 1 ]]; then
  log "Installing Android SDK (platform-tools, platforms;android-${ANDROID_API_LEVEL}, build-tools, ndk)"
  install_android_sdk
fi

if [[ "$ENABLE_LOCALSTACK_TOOLING" -eq 1 ]]; then
  log "Installing LocalStack tooling (localstack, awslocal)"
  install_localstack_tooling
fi

if [[ "$ENABLE_OH_MY_ZSH" -eq 1 ]]; then
  log "Installing Oh My Zsh"
  if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  else
    echo "Oh My Zsh already installed."
  fi
fi

ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
if [[ -d "${HOME}/.oh-my-zsh" ]]; then
  mkdir -p "${ZSH_CUSTOM_DIR}/themes" "${ZSH_CUSTOM_DIR}/plugins"
fi

if [[ "$ENABLE_POWERLEVEL10K" -eq 1 ]]; then
  if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    log "Installing Powerlevel10k theme"
    if [[ ! -d "${ZSH_CUSTOM_DIR}/themes/powerlevel10k" ]]; then
      git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM_DIR}/themes/powerlevel10k"
    else
      echo "Powerlevel10k already installed."
    fi
  else
    log "Skipping Powerlevel10k because Oh My Zsh is not installed"
  fi
fi

install_plugin() {
  local repo="$1"
  local target="$2"
  if [[ ! -d "${target}" ]]; then
    git clone --depth=1 "${repo}" "${target}"
  else
    echo "Plugin already installed: ${target}"
  fi
}

if [[ "$ENABLE_ZSH_PLUGINS" -eq 1 ]]; then
  if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    log "Installing zsh plugins"
    install_plugin "https://github.com/zsh-users/zsh-completions" "${ZSH_CUSTOM_DIR}/plugins/zsh-completions"
    install_plugin "https://github.com/zsh-users/zsh-autosuggestions" "${ZSH_CUSTOM_DIR}/plugins/zsh-autosuggestions"
    install_plugin "https://github.com/zsh-users/zsh-history-substring-search" "${ZSH_CUSTOM_DIR}/plugins/zsh-history-substring-search"
    install_plugin "https://github.com/zsh-users/zsh-syntax-highlighting" "${ZSH_CUSTOM_DIR}/plugins/zsh-syntax-highlighting"
  else
    log "Skipping zsh plugins because Oh My Zsh is not installed"
  fi
fi

if [[ "$ENABLE_SHELL_CONFIG" -eq 1 ]]; then
  log "Configuring shell files"
  ZSHRC="${HOME}/.zshrc"
  if [[ -d "${HOME}/.oh-my-zsh" && ! -f "${ZSHRC}" ]]; then
    cp "${HOME}/.oh-my-zsh/templates/zshrc.zsh-template" "${ZSHRC}"
  fi

  if [[ -f "${ZSHRC}" ]]; then
    backup_file_once "${ZSHRC}"
    sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "${ZSHRC}"

    merge_zsh_plugins "${ZSHRC}" \
      git ssh-agent dotenv zsh-completions zsh-autosuggestions \
      zsh-history-substring-search zsh-syntax-highlighting

    if ! grep -q '### onboarding shell env ###' "${ZSHRC}"; then
      cat <<'EOF' >>"${ZSHRC}"

### onboarding shell env ###
export CODEX_HOME="$HOME/.codex"
eval "$(direnv hook zsh)"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
EOF
    fi

    if ! grep -q '### onboarding ssh-agent autostart ###' "${ZSHRC}"; then
      cat <<'EOF' >>"${ZSHRC}"

### onboarding ssh-agent autostart ###
if command -v ssh-agent >/dev/null 2>&1; then
  if ! pgrep -u "$USER" ssh-agent >/dev/null 2>&1; then
    eval "$(ssh-agent -s)" >/dev/null
  fi
fi
EOF
    fi
  fi

  append_if_missing "${HOME}/.zprofile" 'export PATH="$HOME/.tfenv/bin:$PATH"'
  append_if_missing "${HOME}/.zprofile" 'export PATH="$HOME/.local/bin:$PATH"'
  append_if_missing "${HOME}/.zprofile" 'export PATH="/usr/local/go/bin:$PATH"'
  append_if_missing "${HOME}/.zprofile" 'export PATH="$HOME/go/bin:$PATH"'
  append_if_missing "${HOME}/.zprofile" 'export PATH="$HOME/.dotnet/tools:$PATH"'
  append_if_missing "${HOME}/.zprofile" 'export PATH="$HOME/flutter/bin:$PATH"'
  if [[ -d "${HOME}/Android/Sdk" ]]; then
    append_if_missing "${HOME}/.zprofile" 'export ANDROID_HOME="$HOME/Android/Sdk"'
    append_if_missing "${HOME}/.zprofile" 'export ANDROID_SDK_ROOT="$HOME/Android/Sdk"'
    append_if_missing "${HOME}/.zprofile" 'export PATH="$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator:$HOME/Android/Sdk/cmdline-tools/latest/bin:$PATH"'
  fi
  append_if_missing "${HOME}/.zshenv" '[ -s "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"'
fi

if [[ "$ENABLE_GIT_PROFILE_SCAFFOLD" -eq 1 ]]; then
  log "Scaffolding git work/personal profile config"
  configure_git_profiles
fi

if [[ "$ENABLE_OH_MY_ZSH" -eq 1 ]]; then
  log "Setting default shell to zsh (best effort)"
  if [[ "${SHELL##*/}" != "zsh" ]]; then
    if chsh -s "$(command -v zsh)" "$USER"; then
      echo "Default shell changed to zsh."
    else
      echo "Could not change default shell automatically. Run manually: chsh -s $(command -v zsh)"
    fi
  fi
fi

if [[ "$ENABLE_VSCODE_SETUP" -eq 1 ]]; then
  log "Configuring VS Code WSL settings and installing extensions"
  configure_vscode_wsl
else
  log "Skipping VS Code WSL setup"
fi

log "Setup complete"
echo "Run this now to finish Powerlevel10k setup:"
echo "  zsh -lc 'p10k configure'"
