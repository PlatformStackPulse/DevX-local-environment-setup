# Developer Role Profiles

Profiles describe the intended developer role setup without running installers directly. They are the first step toward role-based onboarding.

The current profile schema is deliberately flat because the existing setup scripts use lightweight flat YAML parsing. Use lowercase `snake_case` keys and scalar values only.

## Naming

- `platform_*` keys declare supported host or runtime platforms.
- `feature_*` keys declare setup capabilities.
- `version_*` keys pin tool versions or channels.
- `notes` gives human-readable constraints, especially for mobile tooling.

## Usage Target

Future setup commands should accept profiles like:

```bash
./scripts/setup-ubuntu-wsl.sh --profile profiles/backend.yaml --dry-run
```

Until profile execution is wired in, treat these files as the source-of-truth role matrix for implementation.
