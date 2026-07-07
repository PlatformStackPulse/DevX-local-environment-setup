# Developer Role Profiles

Profiles describe the intended developer role setup without running installers directly. They are the first step toward role-based onboarding.

The current profile schema is deliberately flat because the existing setup scripts use lightweight flat YAML parsing. Use lowercase `snake_case` keys and scalar values only.

## Naming

- `platform_*` keys declare supported host or runtime platforms. Values are strictly boolean (`true`/`false`).
- `feature_*` keys declare setup capabilities. Values are strictly boolean (`true`/`false`).
- `*_mode` keys qualify a `platform_*` or `feature_*` that is `true` but constrained. They are strings. Recognized values:
  - `full` — fully supported (assumed when no `*_mode` key is present).
  - `partial` — the platform participates, but some tooling must run elsewhere.
  - `host_only` — must run on the host OS, not inside WSL (for example, Android emulators).
  - `macos_only` — requires macOS (for example, Xcode, iOS simulators, CocoaPods).
- `version_*` keys pin tool versions or channels (strings such as `latest`, `lts`, `stable`, `"3.12"`).
- `notes` gives human-readable constraints, especially for mobile tooling.

Keeping `platform_*` and `feature_*` strictly boolean means they parse cleanly through `yaml_get_bool` when `--profile` execution is wired; a constraint on a `true` capability lives in the parallel `*_mode` string (read via `yaml_get_value`). For example: `feature_android_emulator: true` with `feature_android_emulator_mode: host_only`.

## Usage Target

Future setup commands should accept profiles like:

```bash
./setup-ubuntu-wsl.sh --profile profiles/backend.yaml --dry-run
```

Until profile execution is wired in, treat these files as the source-of-truth role matrix for implementation.
