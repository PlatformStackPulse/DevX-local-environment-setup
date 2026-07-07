#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE=""
SETTINGS_ONLY=0
EXTENSIONS_ONLY=0
DRY_RUN=0
DRY_RUN_SET_BY_CLI=0

CONFIGURE_SETTINGS=1
INSTALL_EXTENSIONS=1

EXTENSIONS=(
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
      if (key_part == k) print val_part
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --settings-only)
      SETTINGS_ONLY=1
      shift
      ;;
    --extensions-only)
      EXTENSIONS_ONLY=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      DRY_RUN_SET_BY_CLI=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--config <path>] [--settings-only|--extensions-only] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$CONFIG_FILE" ]]; then
  CONFIG_FILE="${SCRIPT_DIR}/setup-vscode-wsl.yaml"
fi

if [[ -f "$CONFIG_FILE" ]]; then
  if [[ "$DRY_RUN_SET_BY_CLI" -ne 1 ]]; then
    DRY_RUN="$(yaml_get_bool "$CONFIG_FILE" "dry_run" "$DRY_RUN")"
  fi
  CONFIGURE_SETTINGS="$(yaml_get_bool "$CONFIG_FILE" "configure_settings" "$CONFIGURE_SETTINGS")"
  INSTALL_EXTENSIONS="$(yaml_get_bool "$CONFIG_FILE" "install_extensions" "$INSTALL_EXTENSIONS")"
fi

if [[ "${SETTINGS_ONLY}" -eq 1 && "${EXTENSIONS_ONLY}" -eq 1 ]]; then
  echo "Use only one of --settings-only or --extensions-only." >&2
  exit 1
fi

if [[ "${SETTINGS_ONLY}" -eq 1 ]]; then
  CONFIGURE_SETTINGS=1
  INSTALL_EXTENSIONS=0
fi

if [[ "${EXTENSIONS_ONLY}" -eq 1 ]]; then
  CONFIGURE_SETTINGS=0
  INSTALL_EXTENSIONS=1
fi

print_bool() {
  local value="$1"
  if [[ "$value" -eq 1 ]]; then
    printf 'enabled\n'
  else
    printf 'disabled\n'
  fi
}

print_dry_run_plan() {
  echo "Dry-run mode is enabled. No changes will be applied."
  echo "Config file: ${CONFIG_FILE}"
  echo
  echo "Planned actions from feature flags:"
  echo "- configure VS Code settings: $(print_bool "$CONFIGURE_SETTINGS")"
  echo "- install VS Code extensions: $(print_bool "$INSTALL_EXTENSIONS")"

  if [[ "$INSTALL_EXTENSIONS" -eq 1 ]]; then
    echo "- extensions to install (${#EXTENSIONS[@]} total):"
    printf '  - %s\n' "${EXTENSIONS[@]}"
  fi
}

ensure_code_cli() {
  if ! command -v code >/dev/null 2>&1; then
    echo "VS Code CLI 'code' was not found in this WSL shell."
    echo "Open this distro in VS Code Remote WSL and rerun this script."
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command missing: $cmd" >&2
    exit 1
  fi
}

configure_settings() {
  local settings_path
  local settings_dir
  local tmp_file

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

  echo "Configured VS Code WSL settings at ${settings_path}"
}

install_extensions() {
  local -a failed_extensions
  local ext

  failed_extensions=()
  for ext in "${EXTENSIONS[@]}"; do
    if code --install-extension "${ext}" --force; then
      echo "Installed VS Code extension: ${ext}"
    else
      failed_extensions+=("${ext}")
    fi
  done

  if [[ "${#failed_extensions[@]}" -gt 0 ]]; then
    echo "Some VS Code extensions failed to install:"
    printf '  - %s\n' "${failed_extensions[@]}"
    return 1
  fi

  echo "All requested VS Code extensions were installed successfully."
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  print_dry_run_plan
  exit 0
fi

if [[ "${CONFIGURE_SETTINGS}" -eq 1 || "${INSTALL_EXTENSIONS}" -eq 1 ]]; then
  ensure_code_cli
fi

if [[ "${CONFIGURE_SETTINGS}" -eq 1 ]]; then
  require_cmd jq
  configure_settings
fi

if [[ "${INSTALL_EXTENSIONS}" -eq 1 ]]; then
  install_extensions
fi

echo "VS Code WSL setup completed."
