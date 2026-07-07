# Repository Guidelines

Automation that onboards a platform-engineer workstation across three boundaries: the Windows host, Ubuntu-in-WSL, and VS Code Remote WSL. See [README.md](README.md) for the setup guide, per-script options, and the full list of what each script installs. This file captures the conventions an agent needs before editing the scripts — not a usage guide.

## Architecture

Three self-contained scripts, one per platform boundary, intended to run in order. Each pairs with an adjacent YAML feature-flag file of the same name.

1. [setup-windows-wsl.ps1](setup-windows-wsl.ps1) (PowerShell, elevated) → [setup-windows-wsl.yaml](setup-windows-wsl.yaml) — enables WSL2, installs the distro, writes managed `.wslconfig`, fonts, optional winget/VPNKit tooling.
2. [setup-ubuntu-wsl.sh](setup-ubuntu-wsl.sh) (Bash, inside WSL) → [setup-ubuntu-wsl.yaml](setup-ubuntu-wsl.yaml) — cloud CLIs, Terraform/tfenv, language SDKs, zsh + Powerlevel10k, git profile scaffolding, and (optionally) VS Code setup.
3. [setup-vscode-wsl.sh](setup-vscode-wsl.sh) (Bash, inside WSL) → [setup-vscode-wsl.yaml](setup-vscode-wsl.yaml) — VS Code Machine `settings.json` plus the extension list.

Keep new automation at the repo root; there is no src/test/asset tree. Every script follows the same five-stage flow — **defaults → parse CLI args → load YAML overrides → dry-run plan (exit early) → guarded execution**. Match this structure exactly when editing.

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
- **Idempotency is required.** Every install step guards on "already present" (`command -v`, `[[ -d … ]]`, `append_if_missing`, managed-block markers like `### onboarding shell env ###` and `Managed by setup-windows-wsl.ps1`). New steps must be safe to re-run.

## Gotchas

- **The VS Code extension array and `jq` settings block are duplicated** in [setup-vscode-wsl.sh](setup-vscode-wsl.sh) and the `configure_vscode_wsl()` function of [setup-ubuntu-wsl.sh](setup-ubuntu-wsl.sh). Update both together or they drift.
- **CLI flags take precedence over YAML on both platforms.** In the Bash scripts, `--dry-run` is tracked via `DRY_RUN_SET_BY_CLI` and `--skip-vscode` / `--settings-only` / `--extensions-only` are applied *after* the YAML load, so an explicit CLI flag always wins; every other `ENABLE_*` flag is YAML-only (no CLI equivalent). In PowerShell, explicit params win over YAML via `$PSBoundParameters.ContainsKey`. Preserve this — a CLI `--dry-run` must never be silently overridden by YAML.
- **Pinned versions live inline**: nvm `v0.40.3`, `dotnet-sdk-8.0`, distro `Ubuntu-24.04`, and the .NET repo URL hardcodes `ubuntu/24.04`. Update deliberately.
- **CPU architecture is detected via `uname -m`** (`x86_64` / `aarch64`) in the AWS CLI and Go installers — extend both `case` blocks when adding arch-specific installs.

## Validate

No build step or test suite. After any change, run the relevant dry-run and confirm the plan matches the flags (agents should run these automatically):

```bash
./setup-ubuntu-wsl.sh --dry-run
./setup-vscode-wsl.sh --dry-run
```

```powershell
.\setup-windows-wsl.ps1 -DryRun
```

For shell edits, also run `shellcheck setup-ubuntu-wsl.sh setup-vscode-wsl.sh` when available.

## Commit & Pull Requests

History is minimal, so no strict convention is enforced. Use short, imperative subjects (`Add VS Code extension flag`, `Fix Ubuntu dry-run output`). PRs should name the target platform(s), list changed scripts/config, include dry-run output, and flag any command that mutates user profiles, `.wslconfig`, PATH, or installed tooling.

## Security

YAML holds **non-secret configuration only** — no tokens, passwords, PATs, or personal Git identity values (git profiles are scaffolded as placeholders in `configure_git_profiles`). Keep YAML defaults conservative and document any destructive or system-level action.
