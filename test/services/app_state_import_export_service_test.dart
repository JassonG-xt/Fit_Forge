import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/services/app_clock.dart';
import 'package:fit_forge/services/app_state.dart';
import 'package:fit_forge/services/app_state_import_export_service.dart';
import 'package:fit_forge/services/app_state_store.dart';

void main() {
  group('AppStateImportExportService', () {
    test('exportToJson uses injected clock for exportedAt', () {
      final fixedNow = DateTime(2026, 5, 18, 9, 30);
      final service = AppStateImportExportService(
        clock: FixedAppClock(fixedNow),
      );

      final exported =
          json.decode(service.exportToJson(const AppStateSnapshot()))
              as Map<String, dynamic>;

      expect(exported['exportedAt'], fixedNow.toIso8601String());
    });

    test('previewImportJson rejects oversized JSON with existing message', () {
      final service = AppStateImportExportService(
        clock: FixedAppClock(DateTime(2026, 5, 18)),
      );
      final huge = json.encode({
        'version': AppStateSnapshot.currentVersion,
        'padding': List.filled(AppState.maxImportJsonChars + 1, 'x').join(),
      });

      final preview = service.previewImportJson(
        jsonStr: huge,
        currentSnapshot: const AppStateSnapshot(),
      );

      expect(preview.isValid, isFalse);
      expect(preview.error, '导入文件过大，请选择较小的备份文件。');
    });

    test('previewImportJson rejects future versions with existing message', () {
      final service = AppStateImportExportService(
        clock: FixedAppClock(DateTime(2026, 5, 18)),
      );
      const futureVersion = AppStateSnapshot.currentVersion + 1;

      final preview = service.previewImportJson(
        jsonStr: json.encode({'version': futureVersion}),
        currentSnapshot: const AppStateSnapshot(),
      );

      expect(preview.isValid, isFalse);
      expect(preview.error, '不支持的导出版本: $futureVersion');
    });
  });
}
