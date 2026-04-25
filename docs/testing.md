# FitForge Testing Guide

This guide describes the automated test setup that currently exists in the repository.

## Commands

Run the full checked-in suite:

```bash
flutter test
```

Generate coverage locally:

```bash
flutter test --coverage
```

Run static analysis with the same strict settings used in CI:

```bash
flutter analyze --fatal-infos --fatal-warnings
```

## Current Suite Layout

The repository currently contains:

- engine unit tests under `test/engines/`
- model and state tests under `test/models/` and `test/services/`
- widget tests for key screens under `test/screens/`
- a smoke test in `test/widget_test.dart`

The existing suite focuses on:

- plan generation rules
- nutrition calculations
- app-state mutations and persistence behavior
- onboarding entry
- main tab navigation
- home empty state
- settings behavior
- workout session flow

## SharedPreferences in Tests

Widget and service tests use mocked `SharedPreferences` state. This keeps tests hermetic and avoids depending on device storage.

## Coverage Expectations

The project target is `70%+` line coverage, and the current branch meets that threshold. Use `flutter test --coverage` on the current `HEAD` to measure the exact number for your revision.

## What Is Not Present Yet

These test layers are planned but are not checked into the repository today:

- golden visual regression tests
- `integration_test/` end-to-end flows

When either suite is added, update this document and `CONTRIBUTING.md` in the same change so commands and expectations stay accurate.
