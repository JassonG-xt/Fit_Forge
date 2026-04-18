# Contributing to FitForge

Thanks for your interest in improving FitForge! This guide covers the development workflow.

## Development Setup

### Prerequisites
- **Flutter SDK** 3.11.4+ — see [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install)
- **Android Studio** or **VS Code** with Flutter plugin
- **Android SDK** (for Android builds)
- **Chrome** (for Web builds)

### Getting Started
```bash
git clone https://github.com/JassonG-xt/Fit_Forge.git
cd Fit_Forge
flutter pub get
flutter run
```

### Running on Different Platforms
```bash
flutter run                    # Default device
flutter run -d chrome          # Web
flutter run -d <device-id>     # Specific Android device
flutter devices                # List available devices
```

## Project Structure

```
lib/
├── main.dart              # Entry point + Provider setup
├── engines/               # Pure-function business logic (testable)
├── models/                # Immutable data models
├── services/              # App state + platform integrations
├── screens/               # UI pages
├── widgets/brand/         # Custom design-system components
└── theme/                 # Colors, spacing, typography

test/                      # Unit + widget tests
integration_test/          # E2E tests
docs/                      # Architecture documentation
```

## Testing

### Running Tests
```bash
flutter test                              # All unit + widget tests
flutter test --coverage                   # With coverage report
flutter test integration_test/            # E2E tests (needs device)
flutter test --tags golden                # Golden visual-regression tests
```

### Coverage Report
```bash
flutter test --coverage
# Linux/Mac:
genhtml coverage/lcov.info -o coverage/html
# Windows: use lcov via Chocolatey or WSL
```

### Writing Tests
- **Unit tests** go under `test/` mirroring `lib/` structure
- **Widget tests** under `test/screens/`, model pattern: `test/widget_test.dart` (mocks `SharedPreferences`)
- **Golden tests** under `test/widgets/` with `@Tags(['golden'])`
- **Integration tests** under `integration_test/` — one happy path per file

## Code Style

### Formatting
```bash
dart format .                                    # Format all
dart format --set-exit-if-changed .             # CI-style check
```

### Lint
```bash
flutter analyze                                  # Must pass with 0 issues
```

We use **strict** analyzer settings (see `analysis_options.yaml`). All PRs must be warning-free.

### Commit Messages
Use [Conventional Commits](https://www.conventionalcommits.org/):
- `feat:` new feature
- `fix:` bug fix
- `chore:` tooling / dependency updates
- `refactor:` code change that does not alter behavior
- `test:` tests only
- `docs:` documentation only
- `perf:` performance improvement

Example:
```
feat(workout): add rest timer quick-add buttons

Adds +15s / +30s buttons to the rest timer for one-tap extension
during active workouts. Closes #42.
```

## Pull Request Process

1. **Fork** and create a feature branch from `main`:
   ```bash
   git checkout -b feat/my-feature
   ```
2. **Make your changes** and ensure:
   - [ ] `flutter analyze` passes with 0 issues
   - [ ] `flutter test` is all green
   - [ ] `dart format .` has no unformatted files
   - [ ] New code has tests (unit + widget where applicable)
3. **Write a descriptive PR** using the PR template
4. **Link related issues** with `Closes #123` / `Fixes #456`
5. **Wait for CI** to pass all three workflows (ci / release-dry-run / web-deploy)

### What We Look For
- Tests that exercise new behavior (not just happy path)
- No regressions in existing tests
- Clean commit history (squash if many small WIP commits)
- Documentation updates if you change public API or architecture

## Reporting Issues

See [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/) for:
- **Bug reports** — include repro steps, platform, app version
- **Feature requests** — explain the problem first, solution second

## Architecture Decisions

Before major architectural changes (e.g., replacing Provider with Riverpod, switching persistence layer), please **open an issue first** to discuss. These changes affect the entire codebase and should be agreed upon before implementation.

See [`docs/architecture.md`](docs/architecture.md) for the current architecture overview.

## Release Process (Maintainers)

See [`docs/release.md`](docs/release.md) for tag / signing / release workflow.

## Questions?

Open a [Discussion](https://github.com/JassonG-xt/Fit_Forge/discussions) or an issue.
