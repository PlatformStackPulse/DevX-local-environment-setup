# Expansion Plan: Multi-Role Developer Environment Setup

## Context

This repository currently automates workstation setup for a platform-engineering style environment. It has three main setup surfaces:

- `setup-windows-wsl.ps1` for Windows host and WSL enablement.
- `setup-ubuntu-wsl.sh` for Ubuntu/WSL developer tooling.
- `setup-vscode-wsl.sh` for VS Code settings and extension setup inside WSL.

The current model is useful, but it is still mostly a single-path onboarding script. The next goal is to expand it so it can support multiple developer personas:

- Full stack web developers.
- Back end developers.
- DevOps engineers.
- Flutter mobile developers.
- Android native developers with emulators.
- iOS developers with simulators.

The repository should become a small developer-environment platform rather than a collection of unrelated install scripts.

## Current Implementation Status

The first expansion slice has started:

- `profiles/` now contains flat scaffold profiles for base, full stack web, backend, DevOps, Flutter mobile, Android native, and iOS native roles.
- `compose/` now contains starter Compose templates for backend, full-stack, and LocalStack-oriented local services.
- `Makefile` now provides a local `make validate` entry point for script syntax, ShellCheck, formatting, dry-run checks, profile checks, and Compose-template checks.

The existing setup scripts do not consume `--profile` yet. Profile execution should be added after the shared helper extraction phase so role behavior does not duplicate YAML, dry-run, logging, and prerequisite logic.

## Recommended Model

Use a **role profile + shared module + platform adapter** model.

In this model:

- A **profile** describes what a developer role needs.
- A **module** installs or configures one capability, such as Node, Docker, Terraform, Flutter, Android SDK, or VS Code extensions.
- A **platform adapter** handles operating-system differences for Windows, Ubuntu/WSL, Linux, and macOS.

Example command shape:

```bash
./scripts/setup-ubuntu-wsl.sh --profile profiles/devops.yaml --dry-run
./scripts/setup-ubuntu-wsl.sh --profile profiles/fullstack-web.yaml
./scripts/setup-macos.sh --profile profiles/ios-native.yaml
```

For Windows:

```powershell
.\scripts\setup-windows.ps1 -Profile .\profiles\flutter-mobile.yaml -DryRun
```

## Why This Approach Will Work

### 1. It Matches How Developer Tooling Actually Overlaps

The target roles share a lot of tooling. For example:

- Full stack, back end, and DevOps developers all need Git, Docker, VS Code, shell tooling, and cloud CLIs.
- Full stack and Flutter developers both need web debugging and local API support.
- Flutter and Android developers both need Android SDK, platform tools, and emulators.
- DevOps and back end developers both benefit from LocalStack, Postgres, Redis, and Docker Compose.

A profile-based model avoids duplicating the same install logic for every role. The repo can install shared capabilities once, then compose them differently per role.

### 2. It Keeps Operating-System Reality Visible

Mobile development has hard platform constraints:

- Android emulators should be installed on the host OS where hardware acceleration and Android Studio integration work best.
- iOS simulators require macOS and Xcode. They cannot run on Windows or WSL.
- WSL is excellent for Linux toolchains, back end services, Docker workflows, and VS Code Remote development, but it is not the right place to run every GUI or emulator.

Platform adapters make these boundaries explicit. The scripts can say "supported", "unsupported", or "host-only" instead of trying to force every tool into every environment.

### 3. It Preserves Safety

The review report identified safety issues around dry-run behavior, profile edits, JSON parsing, and unpinned installers. Expansion will increase risk unless safety becomes a first-class design rule.

The proposed model makes safety easier because every module can expose:

- A dry-run description.
- A prerequisite check.
- An idempotency check.
- A verification command.
- A rollback or backup step when user files are edited.

This gives every role the same safety behavior without rewriting it six times.

### 4. It Supports Incremental Growth

The repository does not need a huge rewrite. It can grow in phases:

1. Fix the current safety issues.
2. Extract shared functions.
3. Add profiles.
4. Move existing install sections into modules.
5. Add new role-specific modules.
6. Add validation and smoke tests.

This keeps the repo useful during the transition.

### 5. It Makes Testing Practical

Profiles and modules are easier to test than one large script. Each module can be tested with:

- Syntax checks.
- Dry-run output checks.
- Mocked command checks.
- Disposable WSL, Windows, macOS, or container smoke tests.

This is important because the repository modifies real developer machines.

## Target Repository Structure

Recommended end-state:

```text
.
├── README.md
├── AGENTS.md
├── archive/
│   └── REVIEW_REPORT.md
├── EXPANSION_PLAN.md
├── profiles/
│   ├── base.yaml
│   ├── fullstack-web.yaml
│   ├── backend.yaml
│   ├── devops.yaml
│   ├── flutter-mobile.yaml
│   ├── android-native.yaml
│   └── ios-native.yaml
├── scripts/
│   ├── setup-windows.ps1
│   ├── setup-ubuntu-wsl.sh
│   ├── setup-linux.sh
│   ├── setup-macos.sh
│   └── lib/
│       ├── logging.sh
│       ├── yaml.sh
│       ├── dry-run.sh
│       ├── prerequisites.sh
│       ├── profile.sh
│       ├── backup.sh
│       └── vscode.sh
├── modules/
│   ├── core/
│   ├── web/
│   ├── backend/
│   ├── devops/
│   ├── flutter/
│   ├── android/
│   └── ios/
├── compose/
│   ├── docker-compose.fullstack.yaml
│   ├── docker-compose.backend.yaml
│   └── localstack-init/
└── tests/
    ├── shell/
    ├── powershell/
    └── fixtures/
```

This structure keeps the repository understandable:

- `profiles/` tells users what each role installs.
- `scripts/` contains entry points and shared script libraries.
- `modules/` contains install/configure units.
- `compose/` contains local service templates.
- `tests/` contains checks that prevent workstation-breaking regressions.

## Profile Design

Profiles should be declarative YAML files. They should not contain secrets.

Example:

```yaml
name: fullstack-web
description: Full stack web developer workstation

platforms:
  windows: true
  ubuntu_wsl: true
  linux: true
  macos: true

features:
  core: true
  vscode: true
  docker: true
  node: true
  python: true
  postgres_client: true
  redis_client: true
  playwright: true
  localstack: true
  terraform: false
  flutter: false
  android: false
  ios: false

versions:
  node: "lts"
  python: "3.12"
  postgres_client: "16"
```

Profiles should answer three questions:

1. Which platforms are supported?
2. Which modules should run?
3. Which versions or options should those modules use?

## Shared Core Module

Every role should inherit a base profile.

Recommended core tooling:

- Git.
- GitHub CLI.
- SSH client.
- curl, wget, unzip, zip.
- jq.
- ripgrep.
- fd.
- make.
- shellcheck and shfmt for shell script contributors.
- PowerShell Core where useful.
- VS Code or VS Code Remote integration.
- Common fonts for terminal prompts.
- Safe shell profile setup.

Core module rules:

- Never overwrite user shell files without backup.
- Prefer managed blocks for profile changes.
- Use dry-run output for every planned mutation.
- Keep secrets out of YAML.
- Make every install idempotent.

## Role Plans

### Full Stack Web Developers

Purpose: build and run modern web applications with local APIs and local service dependencies.

Add:

- Node.js through `nvm`, `fnm`, or another version manager.
- Corepack, pnpm, and yarn.
- TypeScript.
- ESLint and Prettier.
- Playwright browser dependencies.
- Chrome or Edge developer tooling.
- Docker Compose local services.
- Postgres and Redis clients.
- Optional LocalStack for AWS-backed apps.
- VS Code extensions for JavaScript, TypeScript, React, Vue, Astro, Tailwind, ESLint, Prettier, Docker, and YAML.

Useful verification:

```bash
node --version
corepack --version
pnpm --version
npx playwright --version
docker compose version
```

### Back End Developers

Purpose: build and test APIs, workers, services, and local data integrations.

Add:

- Go.
- .NET SDK.
- Python with `uv` or Poetry.
- Java with Maven or Gradle if required by the organization.
- Docker Compose.
- Postgres, Redis, and optional MongoDB clients.
- LocalStack for AWS service emulation.
- API tooling such as httpie, grpcurl, and Bruno/Postman/Insomnia.
- VS Code extensions for Go, C#, Python, REST clients, Docker, YAML, and database browsing.

Useful verification:

```bash
go version
dotnet --version
python --version
docker compose ps
aws --endpoint-url=http://localhost:4566 sts get-caller-identity
```

### DevOps Engineers

Purpose: support infrastructure, cloud, containers, and deployment workflows.

Add:

- Terraform.
- tfenv or tenv.
- Terragrunt if used.
- AWS CLI.
- Azure CLI.
- Google Cloud CLI.
- kubectl.
- Helm.
- k9s.
- Docker and Docker Compose.
- LocalStack.
- tflint.
- trivy.
- checkov.
- pre-commit.
- act for local GitHub Actions testing where useful.
- kind or minikube for local Kubernetes clusters.

Useful verification:

```bash
terraform version
kubectl version --client
helm version
aws --version
az version
gcloud version
trivy --version
```

### Flutter Mobile Developers

Purpose: build Flutter apps for web, Android, and iOS where platform support exists.

Add:

- Flutter SDK, preferably through FVM for version control.
- Dart tooling through Flutter.
- Android Studio.
- Android SDK.
- Android platform tools.
- Android emulator support on host OS.
- CocoaPods and Xcode checks on macOS for iOS builds.
- VS Code Flutter and Dart extensions.

Useful verification:

```bash
flutter doctor -v
flutter devices
flutter emulators
dart --version
```

### Android Native Developers

Purpose: build native Android applications with Android Studio, Gradle, SDKs, and emulators.

Add on host OS:

- Android Studio.
- Android SDK command-line tools.
- Android platform tools.
- Build tools.
- One default Android platform.
- One default emulator system image.
- Gradle or Gradle wrapper support.
- JDK.
- `ANDROID_HOME`.
- `ANDROID_SDK_ROOT`.
- PATH entries for `platform-tools`, `emulator`, and `cmdline-tools/latest/bin`.

Emulator note:

- Prefer host OS setup for emulators.
- On Windows, use Android Studio and hardware acceleration on the Windows host.
- On macOS, use Android Studio plus Apple Silicon or Intel-compatible emulator images.
- Do not treat WSL as the primary emulator host.

Useful verification:

```bash
adb version
emulator -list-avds
sdkmanager --list
```

### iOS Developers

Purpose: build and run iOS applications with Xcode and iOS simulators.

Supported platform:

- macOS only.

Add:

- Xcode detection.
- Xcode Command Line Tools.
- CocoaPods.
- fastlane.
- Ruby setup if required by mobile pipelines.
- Flutter iOS support if Flutter profile is enabled.
- Simulator discovery and boot checks with `xcrun simctl`.

Unsupported platforms:

- Windows cannot run Xcode or iOS simulators.
- WSL cannot run Xcode or iOS simulators.
- Linux cannot run iOS simulators.

Useful verification:

```bash
xcodebuild -version
xcrun simctl list devices available
pod --version
fastlane --version
```

## Docker Compose and Local Services

The repo should include reusable Compose templates instead of making every application reinvent local infrastructure.

Recommended templates:

- `compose/docker-compose.fullstack.yaml`
- `compose/docker-compose.backend.yaml`
- `compose/docker-compose.localstack.yaml`

Common services:

- Postgres.
- Redis.
- LocalStack.
- DynamoDB admin where useful.
- Mailhog or equivalent local email capture.

Rules:

- Use pinned image tags, not `latest`, where practical.
- Add health checks for databases and LocalStack.
- Use `depends_on` with `condition: service_healthy`.
- Put local secrets in `.env.local`, not committed YAML.
- Include `docker compose ps` and health-check validation in docs.

## Implementation Phases

### Phase 0: Stabilize Current Scripts

Fix the safety issues from `archive/REVIEW_REPORT.md` before expanding.

Deliverables:

- CLI `--dry-run` always wins over YAML.
- `.zshenv` Cargo source is guarded.
- `jq` prerequisite checks exist.
- VS Code JSON parse failures produce a clear error.
- `.zshrc` edits are backed up or managed safely.

Why first:

Expansion will multiply these problems if they remain in shared code.

### Phase 1: Extract Shared Script Libraries

Move repeated logic into reusable helpers.

Deliverables:

- `scripts/lib/logging.sh`
- `scripts/lib/yaml.sh`
- `scripts/lib/dry-run.sh`
- `scripts/lib/prerequisites.sh`
- `scripts/lib/backup.sh`

Why:

The repo needs one implementation of common safety behavior. If dry-run, logging, and YAML parsing are duplicated, role expansion will become fragile.

### Phase 2: Introduce Profiles

Add profile YAML files without changing installer behavior too much.

Deliverables:

- `profiles/base.yaml`
- `profiles/fullstack-web.yaml`
- `profiles/backend.yaml`
- `profiles/devops.yaml`
- `profiles/flutter-mobile.yaml`
- `profiles/android-native.yaml`
- `profiles/ios-native.yaml`

Why:

Profiles make the supported roles visible and reviewable before the module system is fully complete.

### Phase 3: Convert Existing Script Sections into Modules

Move current install sections into module files or clearly separated functions.

Initial modules:

- `core`
- `vscode`
- `cloud-cli`
- `terraform`
- `dotnet`
- `go`
- `node`
- `shell`
- `git-profiles`

Why:

The current Ubuntu script already contains useful modules hidden inside one large file. Extracting them gives the repo a better foundation without discarding working code.

### Phase 4: Add Web, Back End, and DevOps Capabilities

Add the most broadly useful non-mobile roles first.

Deliverables:

- Full stack web profile.
- Back end profile.
- DevOps profile.
- Compose templates for common local services.
- README sections for role-based usage.

Why:

These roles mostly run well on WSL, Linux, and macOS. They are easier to automate safely than emulator-heavy mobile workflows.

### Phase 5: Add Flutter and Android Host Tooling

Add Flutter and Android modules with clear host-vs-WSL boundaries.

Deliverables:

- Flutter SDK or FVM module.
- Android Studio install module.
- Android SDK module.
- Android environment variable module.
- Emulator image selection.
- AVD creation plan or documented manual step.

Why:

Flutter and Android introduce large downloads, GUI applications, and hardware acceleration considerations. They need stronger platform checks and clearer user-facing output.

### Phase 6: Add macOS and iOS Support

Add `setup-macos.sh` for macOS-only setup.

Deliverables:

- Homebrew prerequisite handling.
- Xcode Command Line Tools checks.
- Xcode detection.
- CocoaPods.
- fastlane.
- iOS simulator verification.
- Flutter iOS verification when Flutter is enabled.

Why:

iOS support cannot be bolted onto Windows or WSL. A dedicated macOS path keeps the repo honest and useful.

### Phase 7: Add Tests and CI

Add validation that can run without modifying a developer machine.

Deliverables:

- Bash syntax checks.
- ShellCheck.
- shfmt check.
- PowerShell parser check.
- Profile schema checks.
- Dry-run snapshot checks for each profile.

Why:

This repo changes developer machines. Regression checks should catch unsafe behavior before scripts are run by new engineers.

## Safety Standards for All Modules

Each module should implement:

- `detect`: check whether the tool is already installed.
- `plan`: describe what would happen in dry-run mode.
- `install`: perform the install.
- `verify`: print version or status after install.
- `rollback_note`: explain what changed and where backups were written, if rollback is manual.

Each module should avoid:

- Silent overwrites of user config files.
- Remote shell execution without version pinning or checksum consideration.
- Secrets in committed YAML.
- OS-specific behavior without platform guards.
- GUI/emulator installation from WSL when host setup is required.

## Documentation Plan

Update `README.md` around role-based usage.

Recommended sections:

- Quick start.
- Supported roles.
- Supported platforms.
- Profile examples.
- Dry-run behavior.
- Mobile platform limitations.
- Local services with Docker Compose.
- Troubleshooting.

Add a support matrix:

```text
Role                Windows Host   Ubuntu WSL   Linux   macOS
Full stack web      partial        yes          yes     yes
Back end            partial        yes          yes     yes
DevOps              partial        yes          yes     yes
Flutter mobile      yes            partial      yes     yes
Android native      yes            partial      yes     yes
iOS native          no             no           no      yes
```

Clarify:

- "partial" means the platform participates, but some tooling must run elsewhere.
- iOS simulator support is macOS-only.
- Android emulator support is host-oriented, not WSL-oriented.

## Risks and Mitigations

### Risk: The repo becomes too complex

Mitigation:

- Keep profiles declarative.
- Keep modules small.
- Avoid adding advanced plugin systems until needed.
- Start with three profiles, then expand.

### Risk: Scripts break user machines

Mitigation:

- Dry-run by default for new modules during development.
- Back up modified files.
- Require explicit flags for destructive changes.
- Add validation checks.

### Risk: Mobile tooling is too platform-specific

Mitigation:

- Use platform adapters.
- Document unsupported combinations.
- Keep Android and iOS setup separate.
- Do not hide manual steps that are better completed in Android Studio or Xcode.

### Risk: Reproducibility gets worse

Mitigation:

- Add version fields to profiles.
- Print versions in dry-run output.
- Pin Docker images.
- Use checksum verification for high-risk downloads where practical.

## Success Criteria

This expansion is successful when:

- A developer can choose a role profile and preview all changes with dry-run.
- Full stack, back end, and DevOps setups work from Ubuntu/WSL.
- Flutter and Android setups clearly split WSL tooling from host emulator tooling.
- iOS setup is supported through a macOS script and clearly marked macOS-only.
- Scripts are idempotent and can be rerun safely.
- Every profile has a verification checklist.
- The README explains which roles and platforms are supported.
- CI or local validation catches syntax, formatting, and dry-run regressions.

## Recommended First Milestone

The first milestone should be small and concrete:

1. Fix the current high-priority safety findings.
2. Add `profiles/base.yaml`, `profiles/fullstack-web.yaml`, `profiles/backend.yaml`, and `profiles/devops.yaml`.
3. Extract shared Bash helpers for dry-run, YAML parsing, logging, prerequisites, and backups.
4. Update `README.md` to show role-based dry-run commands.
5. Add ShellCheck and shfmt validation commands to a simple `Makefile`.

After that, add Flutter and Android. Add macOS/iOS last because it needs a separate platform path and cannot be verified from WSL alone.
