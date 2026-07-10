#!/usr/bin/env bash
set -euo pipefail

# macOS developer workstation setup (Homebrew-based).
# Mirrors setup-ubuntu-wsl.sh: defaults -> parse CLI args -> load YAML overrides ->
# dry-run plan (exit early) -> guarded execution. Every step is idempotent.
#
# The tool set is extracted from the real projects under ~/github (Go Lambda backends,
# Terraform atom/molecule modules, Flutter mobile apps, Next.js frontends, LocalStack
# local dev). See TOOLS.md for per-tool provenance.

CONFIG_FILE=""
SKIP_VSCODE=0
DRY_RUN=0
DRY_RUN_SET_BY_CLI=0

# Feature flags (defaults; can be overridden by YAML config).
ENABLE_HOMEBREW=1
ENABLE_BASE_PACKAGES=1
ENABLE_SHELL_QUALITY=1
ENABLE_CLOUD_CLIS=1
ENABLE_TERRAFORM=1
ENABLE_TERRAFORM_QUALITY=1
ENABLE_GO=1
ENABLE_GO_QUALITY=1
ENABLE_DOTNET=0
ENABLE_NODE=1
ENABLE_PYTHON=1
ENABLE_KUBERNETES=1
ENABLE_DOCKER=1
ENABLE_FLUTTER=0
ENABLE_IOS_TOOLING=0
ENABLE_ANDROID_TOOLING=0
ENABLE_LOCALSTACK_TOOLING=0
ENABLE_MEDIA_TOOLS=0
ENABLE_FONTS=1
ENABLE_OH_MY_ZSH=1
ENABLE_POWERLEVEL10K=1
ENABLE_ZSH_PLUGINS=1
ENABLE_SHELL_CONFIG=1
ENABLE_GIT_PROFILE_SCAFFOLD=1
ENABLE_VSCODE_SETUP=1

# Tool versions (pin for reproducible installs; "latest"/"stable" fetch the newest).
GO_VERSION="latest"
NODE_CHANNEL="lts"
DOTNET_SDK_VERSION="8.0"
NVM_VERSION="v0.40.3"
TERRAFORM_VERSION="1.11.3"
FLUTTER_CHANNEL="stable"
JDK_VERSION="17"
PYTHON_FORMULA="python@3.12"
DOCKER_RUNTIME="colima" # colima (lightweight, FOSS) or desktop (Docker Desktop cask)
# Android/iOS pins derived from the real mobile apps (xpeeddating build.gradle: compileSdk 35,
# ndk 27.0.12077973; Makefile: ANDROID_HOME cask path, AVD name; CocoaPods 1.16.2).
ANDROID_API_LEVEL="35"
ANDROID_BUILD_TOOLS="35.0.0"
ANDROID_NDK_VERSION="27.0.12077973"
ANDROID_AVD_NAME="flutter_pixel_7" # empty to skip AVD creation
COCOAPODS_VERSION="1.16.2"

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
  echo "- Homebrew bootstrap: $(print_bool "$ENABLE_HOMEBREW")"
  echo "- base packages (git, gh, jq, yq, ripgrep, fd, direnv, make, git-cliff): $(print_bool "$ENABLE_BASE_PACKAGES")"
  echo "- shell quality (shellcheck, shfmt): $(print_bool "$ENABLE_SHELL_QUALITY")"
  echo "- cloud CLIs (awscli, azure-cli, google-cloud-sdk, eksctl): $(print_bool "$ENABLE_CLOUD_CLIS")"
  echo "- Terraform via tfenv: $(print_bool "$ENABLE_TERRAFORM")"
  echo "- Terraform quality (tflint, terraform-docs, trivy, pre-commit, gitlint): $(print_bool "$ENABLE_TERRAFORM_QUALITY")"
  echo "- Go SDK: $(print_bool "$ENABLE_GO")"
  echo "- Go quality (golangci-lint, govulncheck, gosec, staticcheck, air): $(print_bool "$ENABLE_GO_QUALITY")"
  echo "- .NET SDK: $(print_bool "$ENABLE_DOTNET")"
  echo "- Node.js via nvm + corepack: $(print_bool "$ENABLE_NODE")"
  echo "- Python (${PYTHON_FORMULA}) + pipx: $(print_bool "$ENABLE_PYTHON")"
  echo "- Kubernetes tools (kubectl, helm, k9s): $(print_bool "$ENABLE_KUBERNETES")"
  echo "- Docker runtime (${DOCKER_RUNTIME}): $(print_bool "$ENABLE_DOCKER")"
  echo "- Flutter SDK (~/flutter, ${FLUTTER_CHANNEL}) + web: $(print_bool "$ENABLE_FLUTTER")"
  echo "- iOS tooling (Xcode CLT, Ruby, CocoaPods ${COCOAPODS_VERSION} gem, fastlane): $(print_bool "$ENABLE_IOS_TOOLING")"
  echo "- Android SDK (platform-tools, emulator, platforms;android-${ANDROID_API_LEVEL}, ndk, AVD): $(print_bool "$ENABLE_ANDROID_TOOLING")"
  echo "- LocalStack tooling (localstack, awslocal): $(print_bool "$ENABLE_LOCALSTACK_TOOLING")"
  echo "- media tools (ffmpeg): $(print_bool "$ENABLE_MEDIA_TOOLS")"
  echo "- Nerd Fonts (MesloLGS NF): $(print_bool "$ENABLE_FONTS")"
  echo "- Oh My Zsh: $(print_bool "$ENABLE_OH_MY_ZSH")"
  echo "- Powerlevel10k: $(print_bool "$ENABLE_POWERLEVEL10K")"
  echo "- zsh plugins: $(print_bool "$ENABLE_ZSH_PLUGINS")"
  echo "- shell file configuration: $(print_bool "$ENABLE_SHELL_CONFIG")"
  echo "- git profile scaffolding: $(print_bool "$ENABLE_GIT_PROFILE_SCAFFOLD")"
  echo "- VS Code configuration: $(print_bool "$ENABLE_VSCODE_SETUP")"
  echo
  echo "Pinned tool versions:"
  echo "- Go: ${GO_VERSION}"
  echo "- Node channel: ${NODE_CHANNEL}"
  echo "- .NET SDK: ${DOTNET_SDK_VERSION}"
  echo "- nvm: ${NVM_VERSION}"
  echo "- Terraform (tfenv): ${TERRAFORM_VERSION}"
  echo "- Flutter channel: ${FLUTTER_CHANNEL}"
  echo "- JDK: ${JDK_VERSION}"
  echo "- Python formula: ${PYTHON_FORMULA}"
  echo "- Android API level: ${ANDROID_API_LEVEL} (build-tools ${ANDROID_BUILD_TOOLS}, ndk ${ANDROID_NDK_VERSION})"
  echo "- Android AVD: ${ANDROID_AVD_NAME:-<none>}"
  echo "- CocoaPods: ${COCOAPODS_VERSION}"
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

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command missing: $cmd" >&2
    exit 1
  fi
}

# Idempotent Homebrew formula install. A single formula failure is non-fatal
# (warn and continue) so one unavailable/renamed formula never aborts the run.
brew_install() {
  local formula="$1"
  if brew list --formula "$formula" >/dev/null 2>&1; then
    echo "Already installed (formula): $formula"
  else
    brew install "$formula" || echo "Formula install failed: ${formula} (continuing; re-run to retry)." >&2
  fi
}

# Idempotent Homebrew cask install (also non-fatal on a single failure).
brew_cask_install() {
  local cask="$1"
  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo "Already installed (cask): $cask"
  else
    brew install --cask "$cask" || echo "Cask install failed: ${cask} (continuing; re-run to retry)." >&2
  fi
}

# Idempotent `go install` into $GOBIN/$HOME/go/bin.
go_install() {
  local pkg="$1"
  local bin="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "Already installed (go): $bin"
    return
  fi
  if command -v go >/dev/null 2>&1; then
    GOBIN="${HOME}/go/bin" go install "$pkg" || echo "go install failed for ${pkg}; retry after 'go' is on PATH."
  else
    echo "Skipping 'go install ${pkg}': go is not on PATH yet."
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
    pipx install "$pkg" || echo "pipx install failed for ${pkg}."
  else
    echo "Skipping pipx install of ${pkg}: pipx not available (enable install_python)."
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

install_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    echo "Homebrew already installed: $(brew --version | head -n1)"
  else
    log "Installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Put brew on PATH for this session (Apple Silicon: /opt/homebrew, Intel: /usr/local,
  # untar-anywhere installs: ~/.homebrew or wherever an existing brew already resolves).
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  elif [[ -x "${HOME}/.homebrew/bin/brew" ]]; then
    eval "$("${HOME}/.homebrew/bin/brew" shellenv)"
  elif command -v brew >/dev/null 2>&1; then
    eval "$(brew shellenv)"
  fi
  require_cmd brew
}

install_base_packages() {
  # bash: macOS ships 3.2; some project scripts (git-repo-reconciler) need >= 4.
  # git-lfs, rsync: newer than the macOS system copies; used by runner + sync tooling.
  local pkgs=(
    git gh jq yq wget make coreutils gnupg bash git-lfs rsync
    ripgrep fd tree watch direnv git-cliff
  )
  local pkg
  for pkg in "${pkgs[@]}"; do
    brew_install "$pkg"
  done
}

install_shell_quality() {
  brew_install shellcheck
  brew_install shfmt
  brew_install bats-core
}

install_cloud_clis() {
  brew_install awscli
  brew_install azure-cli
  brew_install eksctl
  brew_cask_install google-cloud-sdk
}

install_terraform_via_tfenv() {
  brew_install tfenv
  if command -v tfenv >/dev/null 2>&1; then
    tfenv install "${TERRAFORM_VERSION}" || true
    tfenv use "${TERRAFORM_VERSION}" || true
    terraform -version | head -n1 || true
  fi
}

install_terraform_quality() {
  # tflint is not in Homebrew core; it ships from the official terraform-linters
  # tap. Homebrew 6.x refuses third-party taps until trusted, so trust it first.
  brew tap terraform-linters/tap >/dev/null 2>&1 || true
  brew trust terraform-linters/tap >/dev/null 2>&1 || true
  brew_install tflint
  brew_install terraform-docs
  brew_install trivy
  brew_install pre-commit
  brew_install gitlint
}

install_go_sdk() {
  if [[ "${GO_VERSION}" == "latest" ]]; then
    brew_install go
  elif brew info "go@${GO_VERSION}" >/dev/null 2>&1; then
    # Homebrew keeps a few versioned formulae, e.g. go@1.23 (pass go_version: "1.23").
    brew_install "go@${GO_VERSION}"
  else
    echo "No Homebrew formula 'go@${GO_VERSION}'; installing the current 'go' formula."
    brew_install go
  fi
  command -v go >/dev/null 2>&1 && go version || true
}

install_go_quality() {
  brew_install golangci-lint
  go_install "golang.org/x/vuln/cmd/govulncheck@latest" govulncheck
  go_install "github.com/securego/gosec/v2/cmd/gosec@latest" gosec
  go_install "honnef.co/go/tools/cmd/staticcheck@latest" staticcheck
  go_install "github.com/air-verse/air@latest" air
  go_install "github.com/git-chglog/git-chglog/cmd/git-chglog@latest" git-chglog
}

install_dotnet_sdk() {
  brew_cask_install dotnet-sdk
  command -v dotnet >/dev/null 2>&1 && dotnet --version || true
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

install_python_tooling() {
  brew_install "${PYTHON_FORMULA}"
  brew_install pipx
  if command -v pipx >/dev/null 2>&1; then
    pipx ensurepath || true
  fi
}

install_kubernetes_tools() {
  brew_install kubectl
  brew_install helm
  brew_install k9s
}

install_docker_runtime() {
  case "${DOCKER_RUNTIME}" in
    desktop)
      brew_cask_install docker
      echo "Launch Docker Desktop once to finish setup."
      ;;
    colima | *)
      brew_install colima
      brew_install docker
      brew_install docker-compose
      brew_install docker-buildx
      echo "Start the Docker engine with: colima start"
      echo "Enable the compose/buildx plugins by adding to ~/.docker/config.json cliPluginsExtraDirs if needed."
      ;;
  esac
}

install_flutter_tooling() {
  # Git-clone to ~/flutter to match the apps' default: FLUTTER ?= $(HOME)/flutter/bin/flutter.
  local flutter_dir="${HOME}/flutter"
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
    echo "Enable device builds with install_android_tooling and (iOS) install_ios_tooling; then run 'flutter doctor'."
  fi
}

install_ios_tooling() {
  if ! xcode-select -p >/dev/null 2>&1; then
    log "Installing Xcode Command Line Tools (a GUI dialog may appear)"
    xcode-select --install || echo "Trigger the install manually with: xcode-select --install"
  else
    echo "Xcode Command Line Tools already installed: $(xcode-select -p)"
  fi
  echo "iOS Simulator builds ('flutter run -d \"iPhone 14 Pro\"') need the full Xcode from the App Store, not only the CLT."
  brew_install ruby
  brew_install fastlane
  # CocoaPods must be the Homebrew-Ruby gem pinned to ${COCOAPODS_VERSION}: the apps
  # reject the macOS system 'pod 1.15.2' (xcodeproj 1.24 needs Ruby 3.x). See TOOLS.md.
  local brew_ruby_bin
  brew_ruby_bin="$(brew --prefix)/opt/ruby/bin"
  if [[ -x "${brew_ruby_bin}/gem" ]]; then
    if "${brew_ruby_bin}/gem" list -i cocoapods -v "${COCOAPODS_VERSION}" >/dev/null 2>&1; then
      echo "CocoaPods ${COCOAPODS_VERSION} already installed (Homebrew Ruby gem)."
    else
      "${brew_ruby_bin}/gem" install cocoapods -v "${COCOAPODS_VERSION}" --user-install ||
        echo "gem install cocoapods ${COCOAPODS_VERSION} failed; retry after 'brew install ruby'." >&2
    fi
  else
    echo "Homebrew Ruby not found; install it first (brew install ruby)." >&2
  fi
  echo "The shell-config block puts Homebrew Ruby + its gem bin ahead of the system 'pod' on PATH."
}

install_android_tooling() {
  brew_install "openjdk@${JDK_VERSION}"
  brew_cask_install android-commandlinetools

  # openjdk@N is keg-only (not symlinked onto PATH). sdkmanager/avdmanager are
  # Java programs, so put this JDK on PATH + JAVA_HOME for the rest of this run,
  # otherwise they fail with "Unable to locate a Java Runtime".
  local jdk_prefix
  jdk_prefix="$(brew --prefix "openjdk@${JDK_VERSION}" 2>/dev/null || true)"
  if [[ -n "${jdk_prefix}" && -d "${jdk_prefix}/bin" ]]; then
    export JAVA_HOME="${jdk_prefix}/libexec/openjdk.jdk/Contents/Home"
    export PATH="${jdk_prefix}/bin:${PATH}"
  fi

  local android_home
  android_home="$(brew --prefix)/share/android-commandlinetools"
  export ANDROID_HOME="${android_home}"
  export ANDROID_SDK_ROOT="${android_home}"

  local sdkmanager="${android_home}/cmdline-tools/latest/bin/sdkmanager"
  if [[ ! -x "${sdkmanager}" ]]; then
    sdkmanager="$(command -v sdkmanager || true)"
  fi
  if [[ -z "${sdkmanager}" || ! -x "${sdkmanager}" ]]; then
    echo "sdkmanager not found under ${android_home}; re-run after the cask installs." >&2
    return 0
  fi

  local img_arch
  case "$(uname -m)" in
    arm64) img_arch="arm64-v8a" ;;
    *) img_arch="x86_64" ;;
  esac

  # Accept licenses, then install the components the apps build against
  # (xpeeddating build.gradle: compileSdk 35, ndk 27.0.12077973).
  yes | "${sdkmanager}" --sdk_root="${android_home}" --licenses >/dev/null 2>&1 || true
  "${sdkmanager}" --sdk_root="${android_home}" \
    "platform-tools" "emulator" "cmdline-tools;latest" \
    "platforms;android-${ANDROID_API_LEVEL}" \
    "build-tools;${ANDROID_BUILD_TOOLS}" \
    "ndk;${ANDROID_NDK_VERSION}" \
    "system-images;android-${ANDROID_API_LEVEL};google_apis;${img_arch}" ||
    echo "Some Android SDK components failed to install; re-run to retry." >&2

  # Create a headless-capable AVD (idempotent). xpeeddating overrides the name to xpeed_pixel7.
  if [[ -n "${ANDROID_AVD_NAME}" ]]; then
    local avdmanager="${android_home}/cmdline-tools/latest/bin/avdmanager"
    if [[ -x "${avdmanager}" ]]; then
      if "${avdmanager}" list avd 2>/dev/null | grep -q "Name: ${ANDROID_AVD_NAME}"; then
        echo "AVD ${ANDROID_AVD_NAME} already exists."
      else
        echo "no" | "${avdmanager}" create avd -n "${ANDROID_AVD_NAME}" \
          -k "system-images;android-${ANDROID_API_LEVEL};google_apis;${img_arch}" -d pixel_7 ||
          echo "AVD creation failed (create one in Android Studio if needed)." >&2
      fi
    fi
  fi

  echo "Android SDK ready at ${android_home} (adb: platform-tools/, emulator: emulator/)."
  echo "ANDROID_HOME/PATH are wired into your shell config; open a new terminal or 'exec zsh'."
}

install_localstack_tooling() {
  pipx_install localstack localstack
  pipx_install awscli-local awslocal
}

install_media_tools() {
  brew_install ffmpeg
}

install_fonts() {
  brew_cask_install font-meslo-lg-nerd-font
}

configure_vscode_macos() {
  local settings_path
  local settings_dir
  local tmp_file
  local ext_file
  local -a extensions
  local -a failed_extensions
  local ext
  local line

  if ! command -v code >/dev/null 2>&1; then
    echo "VS Code CLI 'code' was not found."
    echo "Install VS Code and enable the 'code' command (Command Palette: 'Shell Command: Install code command in PATH'), then rerun with --skip-vscode to skip, or rerun this step."
    return 0
  fi

  settings_path="${HOME}/Library/Application Support/Code/User/settings.json"
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
    .["terminal.integrated.defaultProfile.osx"] = "zsh" |
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

  extensions=()
  ext_file="${SCRIPT_DIR}/vscode-extensions.txt"
  if [[ -f "${ext_file}" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(printf '%s' "$line" | tr -d '[:space:]')"
      [[ -z "$line" ]] && continue
      extensions+=("$line")
    done <"${ext_file}"
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
  CONFIG_FILE="${SCRIPT_DIR}/setup-macos.yaml"
fi

if [[ -f "$CONFIG_FILE" ]]; then
  log "Loading feature flags from ${CONFIG_FILE}"
  if [[ "$DRY_RUN_SET_BY_CLI" -ne 1 ]]; then
    DRY_RUN="$(yaml_get_bool "$CONFIG_FILE" "dry_run" "$DRY_RUN")"
  fi
  ENABLE_HOMEBREW="$(yaml_get_bool "$CONFIG_FILE" "install_homebrew" "$ENABLE_HOMEBREW")"
  ENABLE_BASE_PACKAGES="$(yaml_get_bool "$CONFIG_FILE" "install_base_packages" "$ENABLE_BASE_PACKAGES")"
  ENABLE_SHELL_QUALITY="$(yaml_get_bool "$CONFIG_FILE" "install_shell_quality" "$ENABLE_SHELL_QUALITY")"
  ENABLE_CLOUD_CLIS="$(yaml_get_bool "$CONFIG_FILE" "install_cloud_clis" "$ENABLE_CLOUD_CLIS")"
  ENABLE_TERRAFORM="$(yaml_get_bool "$CONFIG_FILE" "install_terraform" "$ENABLE_TERRAFORM")"
  ENABLE_TERRAFORM_QUALITY="$(yaml_get_bool "$CONFIG_FILE" "install_terraform_quality" "$ENABLE_TERRAFORM_QUALITY")"
  ENABLE_GO="$(yaml_get_bool "$CONFIG_FILE" "install_go" "$ENABLE_GO")"
  ENABLE_GO_QUALITY="$(yaml_get_bool "$CONFIG_FILE" "install_go_quality" "$ENABLE_GO_QUALITY")"
  ENABLE_DOTNET="$(yaml_get_bool "$CONFIG_FILE" "install_dotnet" "$ENABLE_DOTNET")"
  ENABLE_NODE="$(yaml_get_bool "$CONFIG_FILE" "install_node" "$ENABLE_NODE")"
  ENABLE_PYTHON="$(yaml_get_bool "$CONFIG_FILE" "install_python" "$ENABLE_PYTHON")"
  ENABLE_KUBERNETES="$(yaml_get_bool "$CONFIG_FILE" "install_kubernetes_tools" "$ENABLE_KUBERNETES")"
  ENABLE_DOCKER="$(yaml_get_bool "$CONFIG_FILE" "install_docker" "$ENABLE_DOCKER")"
  ENABLE_FLUTTER="$(yaml_get_bool "$CONFIG_FILE" "install_flutter" "$ENABLE_FLUTTER")"
  ENABLE_IOS_TOOLING="$(yaml_get_bool "$CONFIG_FILE" "install_ios_tooling" "$ENABLE_IOS_TOOLING")"
  ENABLE_ANDROID_TOOLING="$(yaml_get_bool "$CONFIG_FILE" "install_android_tooling" "$ENABLE_ANDROID_TOOLING")"
  ENABLE_LOCALSTACK_TOOLING="$(yaml_get_bool "$CONFIG_FILE" "install_localstack_tooling" "$ENABLE_LOCALSTACK_TOOLING")"
  ENABLE_MEDIA_TOOLS="$(yaml_get_bool "$CONFIG_FILE" "install_media_tools" "$ENABLE_MEDIA_TOOLS")"
  ENABLE_FONTS="$(yaml_get_bool "$CONFIG_FILE" "install_fonts" "$ENABLE_FONTS")"
  ENABLE_OH_MY_ZSH="$(yaml_get_bool "$CONFIG_FILE" "install_oh_my_zsh" "$ENABLE_OH_MY_ZSH")"
  ENABLE_POWERLEVEL10K="$(yaml_get_bool "$CONFIG_FILE" "install_powerlevel10k" "$ENABLE_POWERLEVEL10K")"
  ENABLE_ZSH_PLUGINS="$(yaml_get_bool "$CONFIG_FILE" "install_zsh_plugins" "$ENABLE_ZSH_PLUGINS")"
  ENABLE_SHELL_CONFIG="$(yaml_get_bool "$CONFIG_FILE" "configure_shell_files" "$ENABLE_SHELL_CONFIG")"
  ENABLE_GIT_PROFILE_SCAFFOLD="$(yaml_get_bool "$CONFIG_FILE" "configure_git_profiles" "$ENABLE_GIT_PROFILE_SCAFFOLD")"
  ENABLE_VSCODE_SETUP="$(yaml_get_bool "$CONFIG_FILE" "configure_vscode" "$ENABLE_VSCODE_SETUP")"
  GO_VERSION="$(yaml_get_value "$CONFIG_FILE" "go_version" "$GO_VERSION")"
  NODE_CHANNEL="$(yaml_get_value "$CONFIG_FILE" "node_channel" "$NODE_CHANNEL")"
  DOTNET_SDK_VERSION="$(yaml_get_value "$CONFIG_FILE" "dotnet_sdk_version" "$DOTNET_SDK_VERSION")"
  NVM_VERSION="$(yaml_get_value "$CONFIG_FILE" "nvm_version" "$NVM_VERSION")"
  TERRAFORM_VERSION="$(yaml_get_value "$CONFIG_FILE" "terraform_version" "$TERRAFORM_VERSION")"
  FLUTTER_CHANNEL="$(yaml_get_value "$CONFIG_FILE" "flutter_channel" "$FLUTTER_CHANNEL")"
  JDK_VERSION="$(yaml_get_value "$CONFIG_FILE" "jdk_version" "$JDK_VERSION")"
  PYTHON_FORMULA="$(yaml_get_value "$CONFIG_FILE" "python_formula" "$PYTHON_FORMULA")"
  DOCKER_RUNTIME="$(yaml_get_value "$CONFIG_FILE" "docker_runtime" "$DOCKER_RUNTIME")"
  ANDROID_API_LEVEL="$(yaml_get_value "$CONFIG_FILE" "android_api_level" "$ANDROID_API_LEVEL")"
  ANDROID_BUILD_TOOLS="$(yaml_get_value "$CONFIG_FILE" "android_build_tools" "$ANDROID_BUILD_TOOLS")"
  ANDROID_NDK_VERSION="$(yaml_get_value "$CONFIG_FILE" "android_ndk_version" "$ANDROID_NDK_VERSION")"
  ANDROID_AVD_NAME="$(yaml_get_value "$CONFIG_FILE" "android_avd_name" "$ANDROID_AVD_NAME")"
  COCOAPODS_VERSION="$(yaml_get_value "$CONFIG_FILE" "cocoapods_version" "$COCOAPODS_VERSION")"
fi

if [[ "$SKIP_VSCODE" -eq 1 ]]; then
  ENABLE_VSCODE_SETUP=0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  print_dry_run_plan
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script targets macOS. Detected: $(uname -s)." >&2
  echo "Use setup-ubuntu-wsl.sh for Ubuntu/WSL or setup-windows-wsl.ps1 for Windows." >&2
  exit 1
fi

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Do not run this script as root; Homebrew refuses to run under sudo." >&2
  exit 1
fi

if [[ "$ENABLE_HOMEBREW" -eq 1 ]]; then
  install_homebrew
else
  require_cmd brew
fi

if [[ "$ENABLE_BASE_PACKAGES" -eq 1 ]]; then
  log "Installing base packages"
  install_base_packages
fi

if [[ "$ENABLE_SHELL_QUALITY" -eq 1 ]]; then
  log "Installing shell quality tools (shellcheck, shfmt)"
  install_shell_quality
fi

if [[ "$ENABLE_CLOUD_CLIS" -eq 1 ]]; then
  log "Installing cloud CLIs"
  install_cloud_clis
fi

if [[ "$ENABLE_TERRAFORM" -eq 1 ]]; then
  log "Installing Terraform via tfenv (${TERRAFORM_VERSION})"
  install_terraform_via_tfenv
fi

if [[ "$ENABLE_TERRAFORM_QUALITY" -eq 1 ]]; then
  log "Installing Terraform quality tools"
  install_terraform_quality
fi

if [[ "$ENABLE_GO" -eq 1 ]]; then
  log "Installing Go SDK"
  install_go_sdk
fi

if [[ "$ENABLE_GO_QUALITY" -eq 1 ]]; then
  log "Installing Go quality tools"
  install_go_quality
fi

if [[ "$ENABLE_DOTNET" -eq 1 ]]; then
  log "Installing .NET SDK"
  install_dotnet_sdk
fi

if [[ "$ENABLE_NODE" -eq 1 ]]; then
  log "Installing nvm and Node.js toolchain"
  install_nvm_node
fi

if [[ "$ENABLE_PYTHON" -eq 1 ]]; then
  log "Installing Python and pipx"
  install_python_tooling
fi

if [[ "$ENABLE_KUBERNETES" -eq 1 ]]; then
  log "Installing Kubernetes tools"
  install_kubernetes_tools
fi

if [[ "$ENABLE_DOCKER" -eq 1 ]]; then
  log "Installing Docker runtime (${DOCKER_RUNTIME})"
  install_docker_runtime
fi

if [[ "$ENABLE_FLUTTER" -eq 1 ]]; then
  log "Installing Flutter and CocoaPods"
  install_flutter_tooling
fi

if [[ "$ENABLE_IOS_TOOLING" -eq 1 ]]; then
  log "Installing iOS tooling"
  install_ios_tooling
fi

if [[ "$ENABLE_ANDROID_TOOLING" -eq 1 ]]; then
  log "Installing Android command-line tooling"
  install_android_tooling
fi

if [[ "$ENABLE_LOCALSTACK_TOOLING" -eq 1 ]]; then
  log "Installing LocalStack tooling"
  install_localstack_tooling
fi

if [[ "$ENABLE_MEDIA_TOOLS" -eq 1 ]]; then
  log "Installing media tools (ffmpeg)"
  install_media_tools
fi

if [[ "$ENABLE_FONTS" -eq 1 ]]; then
  log "Installing Nerd Fonts"
  install_fonts
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
    # BSD sed (macOS) requires an explicit empty backup suffix argument.
    sed -i '' 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "${ZSHRC}"

    if ! grep -q '### onboarding shell env ###' "${ZSHRC}"; then
      cat <<'EOF' >>"${ZSHRC}"

### onboarding shell env ###
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
elif [[ -x "$HOME/.homebrew/bin/brew" ]]; then
  eval "$("$HOME/.homebrew/bin/brew" shellenv)"
fi
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
EOF
    fi

    if ! grep -q '### onboarding mobile env ###' "${ZSHRC}"; then
      cat <<'EOF' >>"${ZSHRC}"

### onboarding mobile env ###
# Android SDK (Homebrew android-commandlinetools), Flutter (~/flutter), and the
# Homebrew-Ruby CocoaPods gem (must precede the system 'pod'). All guarded on presence.
for _android_home in "$(brew --prefix 2>/dev/null)/share/android-commandlinetools" "$HOME/Library/Android/sdk"; do
  [ -d "$_android_home" ] || continue
  export ANDROID_HOME="$_android_home"
  export ANDROID_SDK_ROOT="$_android_home"
  export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
  break
done
# Homebrew openjdk@17 is keg-only; Android tooling (sdkmanager, Gradle) needs it on PATH + JAVA_HOME.
for _jdk in "$(brew --prefix 2>/dev/null)/opt/openjdk@17" "$(brew --prefix 2>/dev/null)/opt/openjdk"; do
  if [ -x "$_jdk/bin/java" ]; then
    export JAVA_HOME="$_jdk/libexec/openjdk.jdk/Contents/Home"
    export PATH="$_jdk/bin:$PATH"
    break
  fi
done
[ -d "$HOME/flutter/bin" ] && export PATH="$HOME/flutter/bin:$PATH"
if [ -d "$(brew --prefix 2>/dev/null)/opt/ruby/bin" ]; then
  export PATH="$(brew --prefix)/opt/ruby/bin:$PATH"
  _gem_user_bin="$($(brew --prefix)/opt/ruby/bin/ruby -e 'print Gem.user_dir' 2>/dev/null)/bin"
  [ -d "$_gem_user_bin" ] && export PATH="$_gem_user_bin:$PATH"
fi
EOF
    fi
  fi

  append_if_missing "${HOME}/.zprofile" 'export PATH="$HOME/.local/bin:$PATH"'
  append_if_missing "${HOME}/.zprofile" 'export PATH="$HOME/go/bin:$PATH"'
  append_if_missing "${HOME}/.zprofile" 'export PATH="$HOME/.dotnet/tools:$PATH"'
fi

if [[ "$ENABLE_GIT_PROFILE_SCAFFOLD" -eq 1 ]]; then
  log "Scaffolding git work/personal profile config"
  configure_git_profiles
fi

if [[ "$ENABLE_VSCODE_SETUP" -eq 1 ]]; then
  log "Configuring VS Code settings and installing extensions"
  configure_vscode_macos
else
  log "Skipping VS Code setup"
fi

log "Setup complete"
echo "Open a new terminal (or 'exec zsh') so PATH and shell changes take effect."
echo "Then run: zsh -lc 'p10k configure'"
