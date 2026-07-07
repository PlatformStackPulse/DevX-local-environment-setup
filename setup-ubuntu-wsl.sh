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

  extensions=(
    "amazonwebservices.amazon-q-vscode"
    "amazonwebservices.aws-toolkit-vscode"
    "anthropic.claude-code"
    "astro-build.astro-vscode"
    "bierner.markdown-mermaid"
    "catppuccin.catppuccin-vsc"
    "chapar-ai.ai-token-analyzer-by-chapar-ai"
    "clemenspeters.format-json"
    "dbaeumer.vscode-eslint"
    "editorconfig.editorconfig"
    "esbenp.prettier-vscode"
    "github.github-vscode-theme"
    "github.vscode-github-actions"
    "golang.go"
    "google.geminicodeassist"
    "hashicorp.terraform"
    "mechatroner.rainbow-csv"
    "mermaidchart.vscode-mermaid-chart"
    "ms-azure-load-testing.microsoft-testing"
    "ms-azuretools.azure-dev"
    "ms-azuretools.vscode-azure-github-copilot"
    "ms-azuretools.vscode-azure-mcp-server"
    "ms-azuretools.vscode-azureappservice"
    "ms-azuretools.vscode-azurecontainerapps"
    "ms-azuretools.vscode-azurefunctions"
    "ms-azuretools.vscode-azureresourcegroups"
    "ms-azuretools.vscode-azurestaticwebapps"
    "ms-azuretools.vscode-azurestorage"
    "ms-azuretools.vscode-azurevirtualmachines"
    "ms-azuretools.vscode-containers"
    "ms-azuretools.vscode-cosmosdb"
    "ms-dotnettools.csdevkit"
    "ms-dotnettools.csharp"
    "ms-dotnettools.vscode-dotnet-runtime"
    "ms-kubernetes-tools.vscode-kubernetes-tools"
    "ms-vscode.vscode-chat-customizations-evaluations"
    "ms-vscode.vscode-node-azure-pack"
    "ms-windows-ai-studio.windows-ai-studio"
    "openai.chatgpt"
    "redhat.vscode-yaml"
    "saoudrizwan.claude-dev"
    "teamsdevapp.vscode-ai-foundry"
    "ubw.mermaidlens"
    "vue.volar"
    "zhuangtongfa.material-theme"
  )

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
  GO_VERSION="$(yaml_get_value "$CONFIG_FILE" "go_version" "$GO_VERSION")"
  NODE_CHANNEL="$(yaml_get_value "$CONFIG_FILE" "node_channel" "$NODE_CHANNEL")"
  DOTNET_SDK_VERSION="$(yaml_get_value "$CONFIG_FILE" "dotnet_sdk_version" "$DOTNET_SDK_VERSION")"
  NVM_VERSION="$(yaml_get_value "$CONFIG_FILE" "nvm_version" "$NVM_VERSION")"
  TERRAFORM_VERSION="$(yaml_get_value "$CONFIG_FILE" "terraform_version" "$TERRAFORM_VERSION")"
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
