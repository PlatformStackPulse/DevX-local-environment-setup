# Tool Inventory (extracted from real projects)

Every tool the setup scripts install is here because a real project under `~/github`
needs it. This file records the **provenance** — which project, and the evidence
(CI action, `go.mod`, `pubspec.yaml`, `Makefile`, `docker-compose.yml`, pre-commit
config, or a documented `brew install` / `apt install` line).

The tools were mined from:

| Group | Projects |
| --- | --- |
| Go Lambda backends | `go-lambda-template`, `go-template`, `TerraCatalog`, `Chapar-Tech`, `papt`, `xpeeddating`, `smart-survey`, `website`, `sync-ai-assets` |
| Terraform modules | `Terraform-module-base-template`, `terraform-atom-molecule-module-template`, 157× `tf-atom-*-aws` / `tf-molecule-*-aws` |
| Flutter mobile apps | `xpeeddating`, `smart-survey`, `Chapar-Tech` mobile-app |
| Next.js / React frontends | `xpeeddating`, `smart-survey`, `website`, `papt`, `ai-agents-token-analyzer` |
| Static site | `TPP` (Chirpy Jekyll theme) |
| Tooling / CLIs | `git-repo-reconciler`, `sync-ai-assets`, `clone_repos.py` |
| CI runners | `actions-runner`, `github-runner`, `github-selfhosted-runners-docker-image` |
| Factory prereqs | `claude-ai-workflow/.claude/scripts/check-prereqs.sh` |

Where a version differs across projects, the **canonical** column is the value the
scripts install (usually the newest in active use). "Install via" names the feature
flag; see each `setup-*.yaml`.

---

## Runtimes & SDKs

| Tool | Canonical version | Provenance (evidence) | Install via |
| --- | --- | --- | --- |
| **Go** | latest (projects span 1.23 → 1.26.4) | `go.mod` in every backend; CI `actions/setup-go`; `sync-ai-assets` needs 1.26.4 | `install_go` |
| **Node.js** | LTS 20 (papt CI wants 22; runners bundle 20+24) | `actions/setup-node`, `frontend-ci.yml`; `package.json` engines | `install_node` (nvm) |
| **.NET SDK** | 8.0 | factory `check-prereqs`; C# VS Code pack; runner agent uses .NET | `install_dotnet` |
| **Flutter** | stable (pinned 3.22.0 / 3.24.1 in apps) | `subosito/flutter-action`, `pubspec.yaml`, `mobile-app-ci.yml` | `install_flutter` |
| **Dart** | bundled with Flutter (`>=3.3.0 <4.0.0`) | `pubspec.yaml` `environment.sdk` | with Flutter |
| **Java / OpenJDK** | 17 (Temurin) | `actions/setup-java`, `mobile-release-android.yml`; runner `JAVA_HOME=jdk17` | `install_java` |
| **Python 3** | 3.12 | factory `check-prereqs`; `clone_repos.py`, `sync_assets.py`; pre-commit host | `install_python` |
| **Ruby** | 3.x (system 2.6 rejected) | `TPP` gemspec (`~> 3.1`); `xpeeddating` iOS CocoaPods note | macOS `install_ios_tooling` |

## Package managers

| Tool | Canonical | Provenance | Install via |
| --- | --- | --- | --- |
| **pnpm** | 9.15.9 | `packageManager` in `xpeeddating/frontend/web-app`, `pnpm/action-setup` | corepack (`install_node`) |
| **yarn** | stable | corepack default | corepack (`install_node`) |
| **corepack** | bundled with Node | runner `node-next.Dockerfile` | `install_node` |
| **pipx** | latest | pre-commit / gitlint / localstack host | `install_python` |
| **Homebrew** | — | macOS install mechanism (factory `brew install …`) | `install_homebrew` (macOS) |

## Cloud & IaC CLIs

| Tool | Canonical | Provenance | Install via |
| --- | --- | --- | --- |
| **AWS CLI v2** | latest | `aws-actions/configure-aws-credentials`; `aws dynamodb …` in Makefiles; runner base | `install_aws_cli` / `install_cloud_clis` |
| **Azure CLI** | latest | factory; VS Code Azure pack | `install_azure_cli` / `install_cloud_clis` |
| **Google Cloud SDK** | latest | runner `.path` (`~/google-cloud-sdk/bin`) | `install_gcloud_cli` / `install_cloud_clis` |
| **eksctl** | latest | factory `brew install eksctl` | macOS `install_cloud_clis` |
| **Terraform** | 1.11.3 (via tfenv) | `.terraform-version`, `hashicorp/setup-terraform`, 157 modules pin 1.11.3 | `install_terraform` |
| **tfenv** | latest | `make dev-setup` reads `.terraform-version` | `install_tfenv` / `install_terraform` |
| **GitHub CLI (gh)** | latest | factory (required, 8×); `gh workflow run` in Makefiles; runner base | `install_github_cli` |

## Terraform quality & security

| Tool | Canonical | Provenance | Install via |
| --- | --- | --- | --- |
| **tflint** | v0.53.0 (+ ruleset-aws 0.37.0) | `terraform-linters/setup-tflint` (824 CI hits); `.tflint.hcl`; pre-commit | `install_terraform_quality` |
| **terraform-docs** | v0.19.0 | pre-commit `terraform_docs`; CI docs-check (7174 hits) | `install_terraform_quality` |
| **trivy** | 0.58.0 | `aquasecurity/trivy-action` (422 CI hits); pre-commit `terraform_trivy` | `install_terraform_quality` |
| **pre-commit** | latest | `.pre-commit-config.yaml` in every TF module | `install_terraform_quality` |
| **gitlint** | v0.19.1 | pre-commit `commit-msg` hook (conventional commits) | `install_terraform_quality` |

> Not used by these projects (deliberately omitted from defaults): `checkov`,
> `tfsec`, `terragrunt`, `conftest`/OPA — a full-repo sweep found zero references.

## Go quality & security

| Tool | Canonical | Provenance | Install via |
| --- | --- | --- | --- |
| **golangci-lint** | v1.60.3 | `golangci/golangci-lint-action`; `.golangci.yml`; `make lint` | `install_go_quality` |
| **govulncheck** | latest | `go install golang.org/x/vuln/…`; CI security job | `install_go_quality` |
| **gosec** | latest | `go install github.com/securego/gosec/v2…`; CI | `install_go_quality` |
| **staticcheck** | latest | `honnef.co/go/tools` (Go static analysis) | `install_go_quality` |
| **air** | latest | `make dev-setup` / `make watch` (hot reload) | `install_go_quality` |
| **git-chglog** | latest | `git-repo-reconciler/scripts/update-changelog.sh` | `install_go_quality` |

## Containers & local services

| Tool | Canonical | Provenance | Install via |
| --- | --- | --- | --- |
| **Docker Engine** | latest | `docker compose up` in every full stack; `check-docker`; runner-img | `install_docker` |
| **Docker Compose v2** | plugin | `docker-compose.yml` in xpeeddating/smart-survey/website/papt | `install_docker` |
| **Docker Buildx** | plugin | `docker/setup-buildx-action`, runner-img multi-arch builds | `install_docker` |
| **LocalStack** | 4.0 (apps: 3.4 → 4.0) | `docker-compose.yml`; `SERVICES=dynamodb,s3,sqs,sns,events,ssm,secretsmanager,cognito-idp,…` | `compose/` + `install_localstack_tooling` |
| **awslocal** (awscli-local) | latest | `scripts/localstack-init.sh` (seed LocalStack) | `install_localstack_tooling` |
| **dynamodb-admin** | latest | `docker-compose.yml` (DynamoDB UI :8001) | `compose/` |

## Kubernetes

| Tool | Canonical | Provenance | Install via |
| --- | --- | --- | --- |
| **kubectl** | 1.31 | factory `check-prereqs` (required, 4×) | `install_kubernetes_tools` |
| **helm** | latest | factory `check-prereqs` (required, 3×) | `install_kubernetes_tools` |
| **k9s** | latest | `devops` role profile | `install_kubernetes_tools` |

## Shell & general CLIs

| Tool | Canonical | Provenance | Install via |
| --- | --- | --- | --- |
| **shellcheck** | latest | `git-repo-reconciler` lint; TPP devcontainer; this repo's `make lint` | `install_shell_quality` |
| **shfmt** | v3.10.0 | `git-repo-reconciler`/TPP; this repo's `make lint` | `install_shell_quality` |
| **bats-core** | latest | `git-repo-reconciler` shell tests | `install_shell_quality` |
| **yq** | latest (mikefarah) | factory `brew install yq`; YAML processing in scripts | `install_shell_quality` |
| **jq** | latest | ubiquitous JSON processing; factory required | base packages |
| **git-lfs** | latest | runner base image | base packages |
| **rsync** | latest | `sync-ai-assets/sync-claude-assets.sh` | base packages |
| **git-cliff** | latest | `orhun/git-cliff-action`; `.chglog/cliff.toml` | macOS base / CI |
| **direnv, ripgrep, fd, make, curl, wget, unzip, zip** | — | scripts, Makefiles, installers across all repos | base packages |

## Flutter mobile (grounded in `xpeeddating/Makefile` + `frontend/mobile-app/android/app/build.gradle`)

The three real Flutter apps (xpeeddating, smart-survey, Chapar-Tech mobile-app) share one
local-dev shape. The setup scripts provision exactly what the Makefile assumes.

| Tool | Canonical | Provenance (evidence) | Install via |
| --- | --- | --- | --- |
| **Flutter SDK** | stable (apps pin 3.22–3.24) at `~/flutter/bin` | `Makefile` `FLUTTER ?= $(HOME)/flutter/bin/flutter`; `subosito/flutter-action` | `install_flutter` (git clone to `~/flutter`) |
| **Android SDK cmdline-tools** | 11076708 | `Makefile` `ANDROID_HOME ?= .../android-commandlinetools` | mac `install_android_tooling` (cask), Ubuntu `install_android_sdk` (Google zip) |
| **Android platform** | android-35 | `build.gradle` `compileSdk = 35` | `sdkmanager platforms;android-35` |
| **Android build-tools** | 35.0.0 | `build.gradle` compileSdk 35 | `sdkmanager build-tools;35.0.0` |
| **Android NDK** | 27.0.12077973 | `build.gradle` `ndkVersion = "27.0.12077973"` | `sdkmanager ndk;27.0.12077973` |
| **platform-tools (adb)** | latest | `Makefile` `run-mobile-android` (`adb wait-for-device`) | `sdkmanager platform-tools` |
| **emulator + system image + AVD** | AVD `xpeed_pixel7` | `Makefile` `ANDROID_EMULATOR_ID ?= xpeed_pixel7`, headless flags | mac `install_android_tooling` (creates `flutter_pixel_7`; override name); Windows Android Studio |
| **JDK (Temurin/OpenJDK)** | 17 | Android Gradle build; Kotlin 2.0.21 | `install_java` / bundled in Android install |
| **CocoaPods** | 1.16.2 (Homebrew-Ruby **gem**, not the system `pod 1.15.2`) | `Makefile` `BREW_RUBY_BIN`/`RUBY_GEM_BIN`; repo docs pin 1.16.2 | macOS `install_ios_tooling` (`gem install cocoapods -v 1.16.2`) |
| **Ruby** | Homebrew 3.x | `Makefile` (system Ruby 2.6 rejected by xcodeproj 1.24) | macOS `install_ios_tooling` |
| **Xcode** | full app for Simulator (`iPhone 14 Pro`) | `Makefile` `run-mobile-ios` (`xcrun simctl`) | manual (App Store); CLT via `install_ios_tooling` |
| **fastlane** | latest | iOS/Android release pipelines | macOS `install_ios_tooling` |
| **firebase-tools** | on-demand | `mobile-release-*.yml` (App Distribution) | `npm i -g` (documented) |

**Local-dev flow the tools enable** (from `xpeeddating/Makefile`):
`docker compose up -d` (LocalStack 4.0 :4566 + dynamodb-admin :8001) → `go run ./cmd/local-api`
on :8090 → `flutter run -d chrome` (web) / `-d "iPhone 14 Pro"` (iOS Sim) / `-d emulator-5554`
(Android, talks to `10.0.2.2:8090`). So a Flutter-mobile workstation needs: Docker, Go, Node/pnpm,
Flutter, Android SDK (+JDK), and — on macOS — the iOS chain. Enable `install_flutter` +
`install_android_tooling`/`install_android_sdk` (+ macOS `install_ios_tooling`) together.

## Node-managed (installed per-project via pnpm/npm — not globally)

TypeScript, ESLint, Prettier, Next.js, React, Tailwind, Vitest, React Testing Library,
**Playwright** (xpeeddating web e2e), Vite, tsx, `@vscode/vsce`, and the TPP build chain
(Rollup, Babel, PurgeCSS, Stylelint, semantic-release, husky, commitlint) all come from
each project's `package.json`. The workstation only needs Node + a package manager; run
`pnpm install` / `npm ci` inside the repo. Playwright browsers: `npx playwright install --with-deps`.

---

## Platform coverage

| Category | macOS (`setup-macos.sh`) | Ubuntu/WSL (`setup-ubuntu-wsl.sh`) | Windows host (`setup-windows-wsl.ps1`) |
| --- | --- | --- | --- |
| Core CLIs, gh, jq, yq | ✅ Homebrew | ✅ apt + binaries | ⚠️ gh, jq via winget |
| Cloud CLIs | ✅ | ✅ | ⚠️ aws/az/gcloud via winget |
| Terraform + quality | ✅ | ✅ | ⚠️ terraform via winget |
| Go + quality | ✅ | ✅ | — (use WSL) |
| Docker | ✅ colima / Desktop | ✅ Engine + plugins | ✅ Docker Desktop |
| Kubernetes | ✅ | ✅ | ⚠️ kubectl/helm via winget |
| Flutter / Dart | ✅ + CocoaPods | ✅ (web/Linux; emulators host-only) | ✅ Flutter + Android Studio |
| iOS (Xcode, fastlane) | ✅ macOS-only | ❌ unsupported | ❌ unsupported |
| Node + pnpm | ✅ | ✅ | — (use WSL) |

⚠️ = host-side convenience only; the primary toolchain runs in WSL/macOS.
