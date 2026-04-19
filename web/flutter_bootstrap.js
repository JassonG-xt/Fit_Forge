// FitForge custom Flutter Web bootstrap.
//
// Why this file exists:
//   - The default `flutter build web` auto-generates a `flutter_bootstrap.js`.
//     When `web/flutter_bootstrap.js` is present, Flutter uses it as-is and
//     skips the default generation.
//   - We override it to coordinate the first-screen brand spinner: the spinner
//     fades out *after* Flutter's engine is initialized and the first frame
//     has rendered, avoiding a jarring "blank flash" on slow connections.
//
// Two Flutter build-time placeholder tokens follow on their own lines below.
// They expand to the Flutter loader runtime and the build config object.
//
// IMPORTANT: Never mention those two placeholder tokens anywhere else in this
// file (not in comments, not in strings). Flutter's substitution is a global
// string replace — a stray reference will be clobbered with multi-line code
// and will produce a SyntaxError at runtime.
//
// See https://docs.flutter.dev/platform-integration/web/initialization for
// the official contract.

{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();

    // Flutter is now mounted. Fade the brand splash spinner out on the next
    // animation frame so the first Flutter frame has a chance to paint first.
    window.requestAnimationFrame(() => {
      const spinner = document.getElementById('loading-indicator');
      if (!spinner) return;
      spinner.classList.add('fade-out');
      window.setTimeout(() => spinner.remove(), 450);
    });
  },
});
