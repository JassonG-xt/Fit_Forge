import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

/// Flutter test entrypoint. Auto-discovered by `flutter test` when present at
/// the test root.
///
/// Disables [GoogleFonts] runtime fetching so widget tests don't leave pending
/// HTTP futures that cause "Test did not complete" hangs (most visibly in the
/// onboarding test that mounts `MainTabScreen` and its 5 typed-up tabs at once).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
