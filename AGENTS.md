# Repository Guidelines

Automation that onboards developer workstations across Windows host setup, Ubuntu-in-WSL, VS Code Remote WSL, and the emerging role-profile scaffold. See [README.md](README.md) for usage. This file captures the conventions an agent needs before editing the scripts and expansion artifacts.

## Architecture

Four self-contained setup scripts, each paired with an adjacent YAML feature-flag file of the same name. The Windows → Ubuntu → VS Code trio runs in order for a WSL workstation; [setup-macos.sh](setup-macos.sh) is a standalone macOS path.

1. [setup-windows-wsl.ps1](setup-windows-wsl.ps1) (PowerShell, elevated) → [setup-windows-wsl.yaml](setup-windows-wsl.yaml) — enables WSL2, installs the distro, writes managed `.wslconfig`, fonts, optional winget/VPNKit tooling.
2. [setup-ubuntu-wsl.sh](setup-ubuntu-wsl.sh) (Bash, inside WSL) → [setup-ubuntu-wsl.yaml](setup-ubuntu-wsl.yaml) — cloud CLIs, Terraform/tfenv, GitHub CLI, Docker, language SDKs, Terraform/Go quality tools, Kubernetes tools, Python, zsh + Powerlevel10k, git profile scaffolding, and (optionally) VS Code setup.
3. [setup-vscode-wsl.sh](setup-vscode-wsl.sh) (Bash, inside WSL) → [setup-vscode-wsl.yaml](setup-vscode-wsl.yaml) — VS Code Machine `settings.json` plus the shared extension list.
4. [setup-macos.sh](setup-macos.sh) (Bash, macOS) → [setup-macos.yaml](setup-macos.yaml) — Homebrew-based install of the same toolchain plus macOS-only Flutter/iOS tooling. Written to run under macOS's stock bash 3.2 (no associative arrays, no `${var,,}`; uses BSD `sed -i ''`).

Every tool installed is traceable to a real project under `~/github` — [TOOLS.md](TOOLS.md) records the provenance. The VS Code extension list lives once in [vscode-extensions.txt](vscode-extensions.txt) and is read by all three shell scripts.

Expansion scaffolding now lives outside the root scripts:

- `profiles/` contains flat role profiles for future role-based execution.
- `compose/` contains starter Docker Compose templates for local service dependencies.
- `Makefile` contains validation targets.
- `archive/` contains historical review material.

Every script follows the same five-stage flow — **defaults → parse CLI args → load YAML overrides → dry-run plan (exit early) → guarded execution**. Match this structure exactly when editing.

## Adding or changing a feature flag

A flag is only complete when every layer agrees. In the Bash scripts, add all of:

1. A default variable near the top (`ENABLE_X=1`).
2. An entry in `print_dry_run_plan`.
3. A load line inside the `if [[ -f "$CONFIG_FILE" ]]` block: `ENABLE_X="$(yaml_get_bool "$CONFIG_FILE" "install_x" "$ENABLE_X")"`.
4. A guarded execution block: `if [[ "$ENABLE_X" -eq 1 ]]; then … fi` (extract non-trivial work into a `snake_case` function).
5. The `key: value` line in the matching `.yaml` file.
6. A matching note in the README "What Gets Installed" section.

PowerShell mirrors this: a `param()` switch, a `Get-YamlBool` load line guarded by `$PSBoundParameters.ContainsKey`, a `Show-DryRunPlan` entry, and a guarded block.

## Conventions

- **Bash**: `set -euo pipefail`, two-space indent, lowercase `snake_case` functions, uppercase `ENABLE_*` flags. Booleans are stored as integers `1`/`0`, not `true`/`false`. Prefix every privileged command with `${SUDO}` (empty when running as root) — never bare `sudo`. Use `log "…"` for section headers.
- **PowerShell**: four-space indent, approved-verb PascalCase functions (`Ensure-Command`, `Get-YamlBool`), PascalCase params, `Write-Step` for section headers.
- **YAML**: lowercase `snake_case` keys mirroring the script flags. The parsers (`yaml_get_value` / `Get-YamlValue`) are hand-rolled and read **flat `key: value` scalars only** — no nested maps, no lists (one pair of surrounding quotes is stripped). Do not introduce nested YAML. Boolean flags load through `yaml_get_bool`; string/version flags load through `yaml_get_value`.
- **Profiles**: keep profile YAML flat (`platform_*`, `feature_*`, `version_*`, `notes`). `platform_*` / `feature_*` values are **strictly boolean**; a constraint on a `true` capability goes in a parallel `*_mode` string (`partial`, `host_only`, `macos_only`; `full` is the default). `version_*` values are strings. Profiles are not wired into the setup scripts yet; treat them as the role matrix and implementation contract. See [profiles/README.md](profiles/README.md).
- **Compose**: use Compose files without a top-level `version:` key, pin images where practical, include health checks for long-running dependencies, and keep secrets in `.env.local` rather than committed files.
- **Idempotency is required.** Every install step guards on "already present" (`command -v`, `[[ -d … ]]`, `append_if_missing`, managed-block markers like `### onboarding shell env ###` and `Managed by setup-windows-wsl.ps1`). New steps must be safe to re-run.

## Gotchas

- **The VS Code extension list is now a single shared file, [vscode-extensions.txt](vscode-extensions.txt)** — read by `setup-vscode-wsl.sh`, `configure_vscode_wsl()` in [setup-ubuntu-wsl.sh](setup-ubuntu-wsl.sh), and `configure_vscode_macos()` in [setup-macos.sh](setup-macos.sh). Edit that file, not the scripts. The parser skips blank lines and `#` comments. **The `jq` settings block is still duplicated** across those three functions — update all three together or they drift.
- **New tool flags follow the same 6-point rule** (default var, dry-run entry, YAML load line, guarded block, `.yaml` key, README note) in both `setup-ubuntu-wsl.sh` and `setup-macos.sh`. Downloaded/scripted CLIs install to `~/.local/bin` (already on PATH via the shell-config block); `go install` tools land in `~/go/bin`. Arch is mapped to `amd64`/`arm64` via `go_arch()` for binary release URLs — extend it for new arches.
- **CLI flags take precedence over YAML on both platforms.** In the Bash scripts, `--dry-run` is tracked via `DRY_RUN_SET_BY_CLI` and `--skip-vscode` / `--settings-only` / `--extensions-only` are applied *after* the YAML load, so an explicit CLI flag always wins; every other `ENABLE_*` flag is YAML-only (no CLI equivalent). In PowerShell, explicit params win over YAML via `$PSBoundParameters.ContainsKey`. Preserve this — a CLI `--dry-run` must never be silently overridden by YAML.
- **Tool versions are configurable, not hardcoded.** Defaults live inline as `GO_VERSION` / `NODE_CHANNEL` / `DOTNET_SDK_VERSION` / `NVM_VERSION` / `TERRAFORM_VERSION` and are overridable via the matching `*_version` / `*_channel` keys in [setup-ubuntu-wsl.yaml](setup-ubuntu-wsl.yaml). The .NET package-repo URL is derived from `/etc/os-release` `VERSION_ID` behind an Ubuntu-only guard. The Windows distro default (`Ubuntu-24.04`) is still hardcoded in the PowerShell `param()` block — update it deliberately.
- **CPU architecture is detected via `uname -m`** (`x86_64` / `aarch64`) in the AWS CLI and Go installers — extend both `case` blocks when adding arch-specific installs.

## Validate

After any change, run the combined validation target when possible:

```bash
make validate
```

At minimum, run the relevant dry-run and confirm the plan matches the flags:

```bash
./setup-ubuntu-wsl.sh --dry-run
./setup-vscode-wsl.sh --dry-run
```

```powershell
.\setup-windows-wsl.ps1 -DryRun
```

For shell edits, also run `shellcheck -S warning setup-ubuntu-wsl.sh setup-vscode-wsl.sh` when available.

## Commit & Pull Requests

History is minimal, so no strict convention is enforced. Use short, imperative subjects (`Add VS Code extension flag`, `Fix Ubuntu dry-run output`). PRs should name the target platform(s), list changed scripts/config, include dry-run output, and flag any command that mutates user profiles, `.wslconfig`, PATH, or installed tooling.

## Security

YAML holds **non-secret configuration only** — no tokens, passwords, PATs, or personal Git identity values (git profiles are scaffolded as placeholders in `configure_git_profiles`). Keep YAML defaults conservative and document any destructive or system-level action.
