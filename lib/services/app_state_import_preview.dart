import 'app_state_store.dart';

class AppStateImportPreview {
  const AppStateImportPreview.valid(this.snapshot) : error = null;
  const AppStateImportPreview.invalid(this.error) : snapshot = null;

  final AppStateSnapshot? snapshot;
  final String? error;

  bool get isValid => snapshot != null;
}
