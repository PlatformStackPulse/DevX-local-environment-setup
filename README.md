# Local Development Environment Setup

Automation scripts for preparing developer, DevOps, mobile, and platform engineering workstations across macOS, Windows, WSL Ubuntu, and VS Code Remote WSL.

The repository is intentionally small: each setup script lives beside a YAML file that controls which features are enabled. Use dry-run mode first to preview actions before changing the local machine.

Every tool the scripts install is traceable to a real project under `~/github` — see [TOOLS.md](TOOLS.md) for the tool-by-tool provenance (which project, and the evidence).

## Getting Started

New here? The short version:

1. **Pick your entry point.** A fresh Windows machine starts with the Windows script. If you already have Ubuntu in WSL, jump straight to the Ubuntu script. If you only need editor setup, run the VS Code script.
2. **Always preview first.** Every script supports a dry-run that prints exactly what it would do and changes nothing. Run it before the real thing.
3. **Toggle features in YAML.** Each script reads an adjacent `*.yaml` file — set a flag to `true` or `false` to control optional work. Command-line flags override the YAML.
4. **Re-run safely.** Every step is idempotent, so running a script twice will not duplicate or break anything.

Recommended order for a brand-new workstation: **Windows host → Ubuntu in WSL → VS Code**. Each step is independent, so you can run only the ones you need.

**Prerequisites**

- macOS script: macOS on Apple Silicon or Intel; Homebrew is installed automatically if missing. Do not run as root.
- Windows host script: Windows 10/11 with an elevated (Run as Administrator) PowerShell session.
- Ubuntu script: an Ubuntu distro running in WSL2 (installed by the Windows script or manually).
- VS Code script: the `code` CLI available inside WSL (open the distro once via VS Code Remote WSL).

## Repository Contents

| File | Purpose |
| --- | --- |
| `setup-macos.sh` | Installs the macOS developer toolchain via Homebrew: core CLIs, cloud CLIs, Terraform + quality tools, Go + quality tools, Node, Python, Kubernetes tools, Docker, and optional Flutter/iOS/Android/LocalStack tooling. |
| `setup-macos.yaml` | Feature flags for the macOS script. |
| `setup-windows-wsl.ps1` | Enables WSL2, installs/configures the target Ubuntu distro, applies `.wslconfig`, installs fonts, and optionally installs Windows tooling. |
| `setup-windows-wsl.yaml` | Feature flags for the Windows host script. |
| `setup-ubuntu-wsl.sh` | Installs Ubuntu/WSL developer tooling, cloud CLIs, language SDKs, Terraform, GitHub CLI, Docker, Terraform/Go quality tools, Kubernetes tools, Python, shell configuration, Git profiles, and optional VS Code WSL setup. |
| `setup-ubuntu-wsl.yaml` | Feature flags for the Ubuntu/WSL script. |
| `setup-vscode-wsl.sh` | Configures VS Code settings and extensions from inside WSL. |
| `setup-vscode-wsl.yaml` | Feature flags for the VS Code-only script. |
| `vscode-extensions.txt` | Shared VS Code extension list read by all three shell scripts (single source of truth). |
| `TOOLS.md` | Evidence-based tool inventory: each tool mapped to the real project that requires it. |
| `profiles/` | Scaffolded role profiles for full stack, backend, DevOps, Flutter, Android, and iOS developers. |
| `compose/` | Local service templates for backend/full-stack workflows. |
| `Makefile` | Local validation targets for scripts, profiles, and Compose templates. |
| `EXPANSION_PLAN.md` | Roadmap for turning this repo into a multi-role setup platform. |
| `AGENTS.md` | Contributor guidance for future repository changes. |

## Quick Start

### macOS

Run from the repository folder on a Mac (Apple Silicon or Intel). Homebrew is installed automatically if missing:

```bash
./setup-macos.sh --dry-run
./setup-macos.sh
```

Useful options:

```bash
./setup-macos.sh --config ./setup-macos.yaml
./setup-macos.sh --skip-vscode
```

Heavy or role-specific toolchains (`.NET`, Flutter, iOS, Android, LocalStack, media) default to off in `setup-macos.yaml`; enable the ones your role needs. Everything else (core CLIs, cloud CLIs, Terraform + quality tools, Go + quality tools, Node, Python, Kubernetes tools, Docker via Colima) installs by default.

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

## Role Profile Scaffold

The `profiles/` directory starts the expansion toward role-based setup. These profiles are currently design/configuration scaffolds; the existing setup scripts do not consume `--profile` yet.

Available profiles:

| Profile | Intended audience |
| --- | --- |
| `profiles/base.yaml` | Shared baseline for all roles. |
| `profiles/fullstack-web.yaml` | Frontend plus local API/service development. |
| `profiles/backend.yaml` | API, worker, and service developers. |
| `profiles/devops.yaml` | Cloud, Terraform, Kubernetes, and security tooling. |
| `profiles/flutter-mobile.yaml` | Flutter mobile/web developers. |
| `profiles/android-native.yaml` | Native Android developers with host emulators. |
| `profiles/ios-native.yaml` | Native iOS developers on macOS. |

The profile schema is intentionally flat (`key: value`) to match the repository's lightweight YAML parsing. Nested maps and lists should wait until a real parser is introduced.

## Local Service Templates

The `compose/` directory includes starter Docker Compose files for local development dependencies:

```bash
docker compose -f compose/docker-compose.backend.yaml up -d
docker compose -f compose/docker-compose.fullstack.yaml up -d
docker compose -f compose/docker-compose.localstack.yaml up -d
```

These templates provide pinned service images, health checks, and LocalStack baseline resources. They are meant as reusable starting points for role profiles and project-specific local environments.

## What Gets Installed or Configured

The macOS script (Homebrew) can install core CLIs (git, gh, jq, yq, ripgrep, fd, git-cliff, a modern bash), shell quality tools (shellcheck, shfmt, bats), cloud CLIs (AWS, Azure, Google Cloud, eksctl), Terraform via tfenv, Terraform quality tools (tflint, terraform-docs, trivy, pre-commit, gitlint), Go and Go quality tools (golangci-lint, govulncheck, gosec, staticcheck, air), Node via nvm, Python + pipx, Kubernetes tools (kubectl, helm, k9s), a Docker runtime (Colima or Docker Desktop), and optionally .NET, Flutter + CocoaPods, iOS tooling (Xcode CLT, fastlane, Ruby), Android command-line tooling, LocalStack tooling, and ffmpeg. It also installs Nerd Fonts, Oh My Zsh + Powerlevel10k + plugins, Git profile scaffolding, and VS Code settings/extensions.

The Windows script can enable WSL and VirtualMachinePlatform, update WSL, install Ubuntu, write managed `.wslconfig` networking defaults, install Meslo Nerd Fonts, and optionally install Git, GitHub CLI, VS Code, Docker Desktop, Windows Terminal, Terraform, kubectl, Helm, Android Studio, Flutter, VPNKit, and troubleshooting/cloud tools.

The Ubuntu script can install base packages, AWS CLI, Azure CLI, Google Cloud CLI, Terraform + tfenv, GitHub CLI, .NET, Go, Node.js through nvm, Python 3 + pipx, Docker Engine + Compose + Buildx, Terraform quality tools (tflint, terraform-docs, trivy, pre-commit, gitlint), Go quality tools (golangci-lint, govulncheck, gosec, staticcheck, air), Kubernetes tools (kubectl, helm, k9s), shell quality tools (shellcheck, shfmt, bats, yq), and optionally Java (OpenJDK 17), the Flutter SDK, and LocalStack tooling — plus Oh My Zsh, Powerlevel10k, zsh plugins, shell profile blocks, Git profile scaffolding, and VS Code WSL configuration.

The VS Code script can apply editor/terminal/Terraform defaults, the Catppuccin Mocha theme, and the shared extension list from `vscode-extensions.txt`.

### Supported Roles and Platforms

| Role | macOS | Ubuntu/WSL | Windows host |
| --- | --- | --- | --- |
| Full stack web | yes | yes | partial |
| Back end | yes | yes | partial |
| DevOps | yes | yes | partial |
| Flutter mobile | yes | partial (web/Linux; emulators host-only) | yes |
| Android native | yes | partial | yes |
| iOS native | yes | no | no |

"partial" means the platform participates but some tooling must run elsewhere; iOS is macOS-only, and Android emulators are host-oriented. See [TOOLS.md](TOOLS.md) for the full tool-to-project mapping and per-platform install method.

### Flutter mobile apps

The Flutter apps (xpeeddating, smart-survey, Chapar-Tech mobile-app) build against a specific toolchain — the setup scripts install exactly what their Makefiles assume: Flutter at `~/flutter/bin` (their `FLUTTER` default), the Android SDK (platform-tools, `platforms;android-35`, `build-tools;35.0.0`, `ndk;27.0.12077973`), an emulator + AVD, JDK 17, and — on macOS — the iOS chain with **CocoaPods 1.16.2 as a Homebrew-Ruby gem** (the system `pod 1.15.2` is rejected).

Enable the mobile toolchain (all off by default because of download size):

```bash
# macOS — full mobile toolchain (Android + iOS)
./setup-macos.sh --config <(sed 's/^install_flutter:.*/install_flutter: true/; s/^install_android_tooling:.*/install_android_tooling: true/; s/^install_ios_tooling:.*/install_ios_tooling: true/' setup-macos.yaml) --dry-run
# or just edit setup-macos.yaml: install_flutter / install_android_tooling / install_ios_tooling → true
```

```yaml
# setup-ubuntu-wsl.yaml — Flutter web/Linux builds + APK builds (emulators run on the Windows host)
install_flutter: true
install_android_sdk: true
install_java: true
```

The apps then run locally via their own Makefile: `docker compose up -d` (LocalStack) → `go run ./cmd/local-api` (:8090) → `flutter run -d chrome` (web), `-d "iPhone 14 Pro"` (iOS Simulator), or `-d emulator-5554` (Android). iOS Simulator builds also need the full Xcode from the App Store; the script installs only the Command Line Tools. Android emulators need host GPU acceleration, so run them on Windows/macOS rather than inside WSL.

## Validation

There is no build step or automated test suite. Validate changes with the relevant dry-run command:

```bash
./setup-ubuntu-wsl.sh --dry-run
./setup-vscode-wsl.sh --dry-run
./setup-macos.sh --dry-run
```

```powershell
.\setup-windows-wsl.ps1 -DryRun
```

For shell edits, run `shellcheck setup-ubuntu-wsl.sh setup-vscode-wsl.sh setup-macos.sh` when ShellCheck is available.

Or run the combined local validation target:

```bash
make validate
```

## Notes

- Some enterprise access tasks, such as Jira, Bitbucket, Artifactory, cloud role grants, and service-specific permissions, remain manual.
- If the `code` CLI is unavailable in WSL, open the distro through VS Code Remote WSL and rerun the VS Code setup.
- On macOS, the default Docker runtime is Colima (start it with `colima start`); set `docker_runtime: desktop` in `setup-macos.yaml` to use Docker Desktop instead. iOS tooling (Xcode, CocoaPods, fastlane) is macOS-only.
- Android emulator setup is intentionally host-oriented (Windows or macOS), not WSL.
- Review YAML flags before running without `--dry-run`; these scripts can modify system packages, user profiles, WSL config, PATH entries, and installed applications.
