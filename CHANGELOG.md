# Changelog

All notable changes to **FitForge** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned (Sprint 1)
- GitHub Actions CI / Release automation
- Android signing configuration & Play Store–ready APK
- Custom app icon and native splash screen
- Strict lint rules (strict-casts / strict-inference)
- Widget tests for core screens

### Planned (Sprint 2)
- Freezed + json_serializable model refactor
- Full screen widget test coverage (14 screens)
- Golden tests for brand widgets
- Integration test for core happy path
- Test coverage ≥ 70%

### Planned (Sprint 3)
- i18n (Chinese + English)
- Local notifications (rest timer / daily reminders)
- Android Health Connect integration (weight sync)
- Sentry crash reporting
- Architecture documentation

---

## [0.1.0] - 2026-04-15

Initial prototype of the Flutter cross-platform rewrite.

### Added
- **Onboarding flow** — multi-step user profile setup (height, weight, goal, frequency, equipment)
- **PlanEngine** — auto-generate 7-day workout plans
  - Splits: full body / push-pull-legs / upper-lower (based on weekly frequency)
  - Training parameters vary by goal (buildMuscle / loseFat / maintain / endurance) and experience level
  - Exercise selection respects available equipment and prioritizes compound movements
- **NutritionEngine** — macros calculation
  - BMR (Mifflin-St Jeor) → TDEE → calorie target adjusted by goal
  - Protein / carbs / fat split with minimum carb floor
  - Meal plan generation with food suggestions
  - Daily water intake recommendation
- **WorkoutSession tracking**
  - Set-level records (weight / reps / completion)
  - Personal record (PR) detection with `_prCache` incremental update
  - In-progress session persistence for crash recovery
- **Body metrics** — weight / body-fat / circumference tracking with historical charts (`fl_chart`)
- **Achievement system** — 5 types: streak / total workouts / PR / body part mastery / nutrition streak
- **Data export/import** — JSON-based user data migration
- **Light/dark theme** — custom brand design system under `lib/theme/`
- **Brand widgets** — 5 custom components: `HeroCard`, `StatNumber`, `HeatStrip`, `GlowButton`, `ProgressRing`
- **Exercise library** — static JSON of exercises with body-part/equipment filters
- **Food database** — static JSON for nutrition lookups
- **Debounced persistence** — `_persist()` collapses rapid writes into one (100 ms window)

### Fixed
- Widget test timeout by mocking `SharedPreferences`
- 8 bugs surfaced in code review
- All `flutter analyze` warnings

### Technical Foundation
- State management: Provider + ChangeNotifier
- Persistence: SharedPreferences (JSON-encoded)
- Unit tests: `plan_engine_test.dart`, `nutrition_engine_test.dart`, `app_state_test.dart`

[Unreleased]: https://github.com/JassonG-xt/Fit_Forge/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/JassonG-xt/Fit_Forge/releases/tag/v0.1.0
