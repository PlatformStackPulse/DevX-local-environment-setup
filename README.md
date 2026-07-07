# Local Development Environment Setup

Automation scripts for preparing a Developers, DevOps and platform engineer workstation across Windows, WSL Ubuntu, and VS Code Remote WSL.

The repository is intentionally small: each setup script lives beside a YAML file that controls which features are enabled. Use dry-run mode first to preview actions before changing the local machine.

## Repository Contents

| File | Purpose |
| --- | --- |
| `setup-windows-wsl.ps1` | Enables WSL2, installs/configures the target Ubuntu distro, applies `.wslconfig`, installs fonts, and optionally installs Windows tooling. |
| `setup-windows-wsl.yaml` | Feature flags for the Windows host script. |
| `setup-ubuntu-wsl.sh` | Installs Ubuntu/WSL developer tooling, cloud CLIs, language SDKs, Terraform, shell configuration, Git profiles, and optional VS Code WSL setup. |
| `setup-ubuntu-wsl.yaml` | Feature flags for the Ubuntu/WSL script. |
| `setup-vscode-wsl.sh` | Configures VS Code settings and extensions from inside WSL. |
| `setup-vscode-wsl.yaml` | Feature flags for the VS Code-only script. |
| `AGENTS.md` | Contributor guidance for future repository changes. |

## Quick Start

### 1. Windows Host

Run from an elevated PowerShell session:

```powershell
cd C:\path\to\DevX-local-environment-setup
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup-windows-wsl.ps1 -DryRun
.\setup-windows-wsl.ps1
```

Use a custom config file when needed:

```powershell
.\setup-windows-wsl.ps1 -ConfigFile .\setup-windows-wsl.yaml
```

### 2. Ubuntu in WSL

Run from the repository folder inside WSL:

```bash
cd /mnt/c/path/to/DevX-local-environment-setup
./setup-ubuntu-wsl.sh --dry-run
./setup-ubuntu-wsl.sh
```

Useful options:

```bash
./setup-ubuntu-wsl.sh --config ./setup-ubuntu-wsl.yaml
./setup-ubuntu-wsl.sh --skip-vscode
```

### 3. VS Code Only

Use this script when WSL is already set up and only VS Code settings/extensions need to be applied:

```bash
./setup-vscode-wsl.sh --dry-run
./setup-vscode-wsl.sh
```

Useful options:

```bash
./setup-vscode-wsl.sh --settings-only
./setup-vscode-wsl.sh --extensions-only
./setup-vscode-wsl.sh --config ./setup-vscode-wsl.yaml
```

## Feature Flags

Each script reads its adjacent YAML file by default. Set a flag to `true` or `false` to control optional work before running the script.

Common examples:

```yaml
dry_run: false
install_terraform: true
configure_vscode_wsl: true
install_mobile_tooling: false
```

The Ubuntu script also accepts tool-version pins (`go_version`, `node_channel`, `dotnet_sdk_version`, `nvm_version`, `terraform_version`). Use `latest` to always fetch the newest, or pin a specific value (for example `go_version: "1.24.4"`) for reproducible installs. Passing `--dry-run` on the command line always overrides `dry_run` in YAML.

YAML files are for non-secret configuration only. Do not store tokens, passwords, personal access keys, or machine-specific credentials in this repository.

## What Gets Installed or Configured

The Windows script can enable WSL and VirtualMachinePlatform, update WSL, install Ubuntu, write managed `.wslconfig` networking defaults, install Meslo Nerd Fonts, and optionally install Git, VS Code, Docker Desktop, Windows Terminal, Android Studio, Flutter, VPNKit, and troubleshooting/cloud tools.

The Ubuntu script can install base packages, AWS CLI, Azure CLI, Google Cloud CLI, Terraform, tfenv, .NET, Go, Node.js through nvm, Oh My Zsh, Powerlevel10k, zsh plugins, shell profile blocks, Git profile scaffolding, and VS Code WSL configuration.

The VS Code script can apply editor/terminal/Terraform defaults, the Catppuccin Mocha theme, and the configured WSL extension list.

## Validation

There is no build step or automated test suite. Validate changes with the relevant dry-run command:

```bash
./setup-ubuntu-wsl.sh --dry-run
./setup-vscode-wsl.sh --dry-run
```

```powershell
.\setup-windows-wsl.ps1 -DryRun
```

For shell edits, run `shellcheck setup-ubuntu-wsl.sh setup-vscode-wsl.sh` when ShellCheck is available.

## Notes

- Some enterprise access tasks, such as Jira, Bitbucket, Artifactory, cloud role grants, and service-specific permissions, remain manual.
- If the `code` CLI is unavailable in WSL, open the distro through VS Code Remote WSL and rerun the VS Code setup.
- Android emulator setup is intentionally Windows-host oriented.
- Review YAML flags before running without `--dry-run`; these scripts can modify system packages, user profiles, WSL config, PATH entries, and installed applications.
