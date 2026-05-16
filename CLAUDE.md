# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Running Flutter / Dart Commands

**Flutter SDK lives on the Windows side; WSL bash cannot execute `flutter.exe` or the bundled `dart`.**

Always run `flutter` / `dart` via PowerShell — either by invoking PowerShell yourself (the assistant) through WSL → Windows interop, or by handing the exact PowerShell command back to the user when interop is unavailable.

Assistant-side pattern (preferred — keeps real output in the conversation):

```bash
powershell.exe -NoProfile -Command "Set-Location E:\Exercise; <flutter or dart command>"
```

Examples:

```bash
powershell.exe -NoProfile -Command "Set-Location E:\Exercise; dart format lib test"
powershell.exe -NoProfile -Command "Set-Location E:\Exercise; flutter analyze --fatal-infos --fatal-warnings"
powershell.exe -NoProfile -Command "Set-Location E:\Exercise; flutter test test/agent/mock_agent_client_test.dart"
powershell.exe -NoProfile -Command "Set-Location E:\Exercise; flutter test"
```

Rules:
- **Never** run bare `flutter` / `dart` from WSL bash — it resolves to `/mnt/e/Flutter/flutter/bin/dart` whose dart-sdk binary is a Windows `.exe` and fails with "No such file or directory".
- **Never** claim "tests passed" / "analyze clean" from a forecast — paste the real PowerShell output (or the user-pasted PowerShell output) before marking validation done.
- Long-running suites (`flutter test`) may need the Bash tool's `timeout` raised — keep it ≤ 600000 ms (10 min) and pipe through `powershell.exe` so the Windows-side test runner owns the process.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
