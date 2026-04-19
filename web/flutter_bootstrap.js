// FitForge custom Flutter Web bootstrap.
//
// Why this file exists:
//   - The default `flutter build web` auto-generates a `flutter_bootstrap.js`
//     that simply initializes the engine and runs the app.
//   - We override it to coordinate the first-screen brand spinner: the spinner
//     fades out *after* Flutter's engine is initialized and the first frame has
//     rendered, avoiding a jarring "blank flash" on slow connections.
//
// Flutter will pick up this file as-is during `flutter build web` and skip its
// default generation. Build-time placeholders {{flutter_js}} and
// {{flutter_build_config}} are substituted by the Flutter tool.
//
// See https://docs.flutter.dev/platform-integration/web/initialization for the
// official contract.

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
