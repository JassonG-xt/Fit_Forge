# FitForge Release Guide

This guide documents the release and deployment flow that is currently wired into the repository.

## Version Sources

Today the version is represented in three places:

- `pubspec.yaml`
  Source of truth for Flutter build version and Android/iOS bundle version metadata.
- `CHANGELOG.md`
  Human-readable release history.
- `lib/screens/settings/settings_screen.dart`
  Current in-app About version label.

When bumping a version, update all three in the same change.

## Current Release Line

The repository is currently aligned around the pre-release line:

- app version: `1.0.0-alpha+1`
- git tag: `v1.0.0-alpha`

The changelog reflects that alpha tag as the latest recorded release.

## Android Release Workflow

Android releases are built by `.github/workflows/release.yml`.

Trigger:

- push a tag matching `v*`

Artifacts produced:

- split APKs for `arm64-v8a`, `armeabi-v7a`, and `x86_64`
- one Android App Bundle (`.aab`)

### Signing

The workflow expects these GitHub secrets when producing a signed release:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

Locally, `android/key.properties.template` documents the expected key file shape. Release builds must be signed with the configured release key; debug signing is not used for release artifacts.

## Web Deployment

Web deployment is handled by `.github/workflows/web-deploy.yml`.

Trigger:

- push to `main` or `master`
- manual `workflow_dispatch`

Build notes:

- the workflow builds with `--base-href "/Fit_Forge/"`
- `build/web/index.html` is copied to `404.html` for SPA fallback on GitHub Pages
- the artifact is checked before upload so `index.html`, `404.html`, and the `/Fit_Forge/` base href are present
- the built artifact is served locally and smoke-tested with `curl` before upload
- the workflow uploads `build/web` with `actions/upload-pages-artifact`
- the workflow publishes through `actions/deploy-pages`, so the repository Pages source should be set to **GitHub Actions**

First-time setup still needs a maintainer to enable Pages in GitHub:

1. Open `Settings -> Pages`.
2. Under `Build and deployment`, set `Source` to **GitHub Actions**.
3. Re-run `Deploy Web Demo` or push another commit to `main`.

If `actions/configure-pages` fails before Flutter starts building, Pages is usually not enabled or is not configured for GitHub Actions. The default `GITHUB_TOKEN` can deploy to Pages, but it cannot enable Pages for the repository by itself.

If the public demo returns 404 after a successful push, check the latest `Deploy Web Demo` run first. A 404 usually means the workflow has not completed successfully, the Pages source is not configured for GitHub Actions deployments, or the local workflow changes have not been pushed to `main` / `master` yet.

## CI Expectations

`.github/workflows/ci.yml` runs on pushes to `main` / `master` and on pull requests. It currently verifies:

- dependency resolution
- formatting on pushes and pull requests
- strict static analysis
- test execution with coverage upload
- minimum 75% total line coverage and 90% coverage for `lib/engines/` plus `lib/services/`

## Local Release Commands

Build Android release artifacts locally:

```bash
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

Build the web demo locally:

```bash
flutter build web --release --base-href /Fit_Forge/
```

## Tagging Convention

Use semantic version tags with an optional pre-release suffix:

- stable: `v1.2.3`
- pre-release: `v1.2.3-alpha`, `v1.2.3-beta`, `v1.2.3-rc1`

The release workflow marks tags containing `-alpha`, `-beta`, or `-rc` as prereleases on GitHub.
