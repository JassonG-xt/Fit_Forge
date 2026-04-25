# FitForge Architecture

This document describes the architecture that is currently checked into the repository.

## High-Level Shape

FitForge is a Flutter application with one in-memory source of truth, local-only persistence, and pure business-logic engines for plan generation and nutrition calculations.

- App entrypoint: `lib/main.dart`
- Global state container: `lib/services/app_state.dart`
- Persistence boundary: `lib/services/app_state_store.dart`
- Pure business logic: `lib/engines/`
- UI surfaces: `lib/screens/`
- Shared design system: `lib/theme/` and `lib/widgets/brand/`

## Runtime Flow

1. `main()` creates `AppState`, awaits `init()`, and injects it with `ChangeNotifierProvider`.
2. `AppState.init()` loads bundled exercise and food JSON, restores persisted state from `SharedPreferences`, rebuilds derived caches, and checks whether a workout session can be recovered.
3. `FitForgeApp` chooses between onboarding and the main tab shell based on `hasCompletedOnboarding`.
4. Screens read and mutate state through `AppState` methods rather than writing to storage directly.

## Module Boundaries

### `lib/engines/`

Pure Dart logic with no Flutter widget dependency.

- `plan_engine.dart`
  Generates 7-day plans from the user profile, exercise library, and training rules.
- `nutrition_engine.dart`
  Computes calorie targets, macro splits, meal suggestions, and water intake.

These files are the easiest place to add or refine domain rules because they are already covered by unit tests.

### `lib/models/`

Hand-written Dart models for domain data, including:

- user profile
- exercises and food data
- workout plans and sessions
- body metrics
- achievements

Serialization lives on the model types themselves via `toJson` / `fromJson`.

### `lib/services/`

Application state and persistence coordination.

- `app_state.dart`
  The in-memory source of truth. Owns profile state, active plan, sessions, body metrics, achievements, theme mode, import/export, and recoverable workout handling.
- `app_state_store.dart`
  The only layer that talks to `SharedPreferences`.
- `session_queries.dart`
  Read-only helpers for deriving streaks, weekly activity, last weights, and similar session views.

This boundary keeps widgets from knowing storage keys or JSON encoding details.

### `lib/screens/`

Feature-oriented screens grouped by surface:

- onboarding
- home
- plan generation
- workout session flow
- nutrition
- progress
- settings
- more

`lib/screens/main_tab_screen.dart` uses an `IndexedStack` so the five primary tabs stay mounted while the selected tab changes.

### `lib/theme/` and `lib/widgets/`

The design system lives in theme tokens plus a small set of custom brand widgets such as `HeroCard`, `GlowButton`, and `ProgressRing`.

## Persistence Model

FitForge is offline-first.

- Durable user state is stored in `SharedPreferences`.
- `AppState` debounces writes to collapse rapid updates into a single persistence pass.
- In-progress workout session data is stored separately so the app can recover an interrupted session after a crash or process kill.
- Import/export is JSON-based and flows through `AppState`, not through ad hoc widget logic.

## Data Sources

Bundled JSON assets live under `assets/data/`.

- `exercise_library.json`
- `food_database.json`

These are loaded through `rootBundle` during `AppState.init()`.

## Testing Boundaries

The current test suite reflects the architecture:

- engines are covered by unit tests
- state and persistence logic are covered by service tests
- selected screens and navigation contracts are covered by widget tests

See [testing.md](testing.md) for commands and current scope.
