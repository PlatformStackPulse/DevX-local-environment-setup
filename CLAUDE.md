# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Workstation-onboarding automation: a small set of self-contained setup scripts that install developer/DevOps/mobile toolchains across macOS, Windows host, Ubuntu-in-WSL, and VS Code Remote WSL. There is no application code, no build step, and no test suite — the deliverable is the scripts themselves and their YAML feature flags.

[AGENTS.md](AGENTS.md) holds the full contributor conventions (per-language style, the flag-addition checklist, gotchas). Read it before editing scripts. This file is the orientation layer.

## Commands

```bash
make validate       # runs lint + dry-run + profiles + compose checks (do this after any change)
make lint           # bash -n, shellcheck -S warning, shfmt -d -i 2 -ci on the shell scripts
make dry-run        # runs each shell script with --dry-run
```

Per-script dry-run (always preview before a real run — every script mutates system packages, profiles, PATH, `.wslconfig`):

```bash
./setup-macos.sh --dry-run
./setup-ubuntu-wsl.sh --dry-run
./setup-vscode-wsl.sh --dry-run
.\setup-windows-wsl.ps1 -DryRun         # elevated PowerShell on the Windows host
```

There is no "single test" — the equivalent of running a test is running the relevant `--dry-run` and confirming the printed plan matches the enabled flags. Shellcheck directly when editing a single script: `shellcheck -S warning setup-macos.sh`.

## Architecture

Four independent script + YAML pairs (same basename). For a WSL workstation the order is Windows → Ubuntu → VS Code; macOS is a standalone path.

| Script | Runtime | Config | Role |
| --- | --- | --- | --- |
| [setup-windows-wsl.ps1](setup-windows-wsl.ps1) | PowerShell, elevated | [setup-windows-wsl.yaml](setup-windows-wsl.yaml) | Enable WSL2, install distro, `.wslconfig`, fonts, optional winget tooling |
| [setup-ubuntu-wsl.sh](setup-ubuntu-wsl.sh) | Bash, in WSL | [setup-ubuntu-wsl.yaml](setup-ubuntu-wsl.yaml) | Cloud CLIs, language SDKs, Terraform, Docker, k8s/quality tools, zsh, git profiles |
| [setup-vscode-wsl.sh](setup-vscode-wsl.sh) | Bash, in WSL | [setup-vscode-wsl.yaml](setup-vscode-wsl.yaml) | VS Code `settings.json` + shared extensions |
| [setup-macos.sh](setup-macos.sh) | Bash, macOS | [setup-macos.yaml](setup-macos.yaml) | Homebrew install of the same toolchain + macOS-only Flutter/iOS |

Every script follows the same five-stage flow — **defaults → parse CLI args → load YAML overrides → dry-run plan (exit early) → guarded execution**. Match this exactly; the flow lives at the top-level of each script (see `CONFIG_FILE` handling around [setup-macos.sh:661](setup-macos.sh#L661)).

Key shared facts:
- **`vscode-extensions.txt` is the single source of truth** for extensions, read by `setup-vscode-wsl.sh`, `configure_vscode_wsl()`, and `configure_vscode_macos()`. Edit the file, not the scripts. The `jq` settings block, however, is still **duplicated** across those three functions — update all three together or they drift.
- **Every installed tool traces to a real project** under `~/github`; [TOOLS.md](TOOLS.md) records the provenance. Don't add a tool without a project justification.
- **YAML parsing is hand-rolled and flat only** (`yaml_get_value` / `yaml_get_bool` in Bash, `Get-YamlValue` / `Get-YamlBool` in PS): `key: value` scalars, no nested maps or lists. Booleans are stored as integers `1`/`0`. Don't introduce nested YAML.
- **macOS script targets stock bash 3.2**: no associative arrays, no `${var,,}`, BSD `sed -i ''`.
- **CLI flags win over YAML**: `--dry-run` (tracked via `DRY_RUN_SET_BY_CLI`) and `--skip-vscode` / `--settings-only` / `--extensions-only` apply after the YAML load. Preserve this precedence.

Non-script scaffolding: `profiles/` (flat role-profile YAML — a design contract, **not yet wired into the scripts**), `compose/` (starter Docker Compose templates, no top-level `version:` key), `EXPANSION_PLAN.md` (roadmap).

## Adding or changing a feature flag

A flag is only complete when every layer agrees. In the Bash scripts add all six:
1. Default variable near the top (`ENABLE_X=1`).
2. Entry in `print_dry_run_plan`.
3. Load line in the `if [[ -f "$CONFIG_FILE" ]]` block: `ENABLE_X="$(yaml_get_bool "$CONFIG_FILE" "install_x" "$ENABLE_X")"`.
4. Guarded execution block: `if [[ "$ENABLE_X" -eq 1 ]]; then … fi` (extract non-trivial work into a `snake_case` function).
5. The `key: value` line in the matching `.yaml`.
6. A note in the README "What Gets Installed" section.

PowerShell mirrors this: a `param()` switch, a `Get-YamlBool` load guarded by `$PSBoundParameters.ContainsKey`, a `Show-DryRunPlan` entry, and a guarded block.

## Idempotency & safety

Every install step must guard on "already present" (`command -v`, `[[ -d … ]]`, `append_if_missing`, managed-block markers like `### onboarding shell env ###`) — re-running a script must never duplicate or break anything. Prefix privileged Bash commands with `${SUDO}` (empty when root), never bare `sudo`. YAML holds **non-secret config only** — no tokens, passwords, PATs, or git identity values (git profiles are placeholder scaffolds).
