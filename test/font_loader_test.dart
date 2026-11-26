import 'dart:math' as math;

import 'package:ccc_accounting_management/core/theme/app_theme.dart';
import 'package:ccc_accounting_management/core/theme/font_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFontLoader extends FontLoader {
  _FakeFontLoader(super.family, {this.shouldFailOnLoad = false});

  final bool shouldFailOnLoad;
  final List<Uint8List> loadedBytes = [];
  int loadCalls = 0;

  @override
  Future<void> loadFont(Uint8List list, String family) async {
    loadedBytes.add(list);
  }

  @override
  Future<void> load() async {
    loadCalls++;
    if (shouldFailOnLoad) {
      throw StateError('load failed');
    }
    await super.load();
  }
}

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadExtendedFonts', () {
    test('loads Regular and Bold ext font assets into PretendardExt', () async {
      final requestedAssets = <String>[];
      late _FakeFontLoader createdLoader;

      await loadExtendedFonts(
        createFontLoader: (family) {
          createdLoader = _FakeFontLoader(family);
          return createdLoader;
        },
        loadAsset: (key) async {
          requestedAssets.add(key);
          return ByteData.sublistView(
            Uint8List.fromList([requestedAssets.length]),
          );
        },
      );

      expect(createdLoader.family, AppTheme.extFontFamily);
      expect(createdLoader.loadCalls, 1);
      expect(requestedAssets, [
        'assets/fonts/PretendardExt-Regular.ttf',
        'assets/fonts/PretendardExt-Bold.ttf',
      ]);
      expect(createdLoader.loadedBytes.length, 2);
    });

    test('fails silently when asset loading throws', () async {
      await expectLater(
        loadExtendedFonts(
          createFontLoader: _FakeFontLoader.new,
          loadAsset: (_) => Future<ByteData>.error(Exception('network error')),
        ),
        completes,
      );
    });

    test('fails silently when FontLoader.load throws', () async {
      await expectLater(
        loadExtendedFonts(
          createFontLoader: (family) =>
              _FakeFontLoader(family, shouldFailOnLoad: true),
          loadAsset: (_) async => ByteData(4),
        ),
        completes,
      );
    });
  });

  group('AppTheme font fallback and contrast', () {
    test('sets PretendardExt fallback on theme text styles', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        expect(theme.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
        expect(
          theme.textTheme.bodyMedium?.fontFamilyFallback,
          AppTheme.fontFamilyFallback,
        );
        expect(
          theme.filledButtonTheme.style?.textStyle
              ?.resolve(const {})
              ?.fontFamilyFallback,
          AppTheme.fontFamilyFallback,
        );
        expect(
          theme.outlinedButtonTheme.style?.textStyle
              ?.resolve(const {})
              ?.fontFamilyFallback,
          AppTheme.fontFamilyFallback,
        );
        expect(
          theme.textButtonTheme.style?.textStyle
              ?.resolve(const {})
              ?.fontFamilyFallback,
          AppTheme.fontFamilyFallback,
        );
        expect(
          theme.chipTheme.labelStyle?.fontFamilyFallback,
          AppTheme.fontFamilyFallback,
        );
        expect(
          theme.navigationBarTheme.labelTextStyle
              ?.resolve(const {})
              ?.fontFamilyFallback,
          AppTheme.fontFamilyFallback,
        );
        expect(
          theme.snackBarTheme.contentTextStyle?.fontFamilyFallback,
          AppTheme.fontFamilyFallback,
        );
        expect(
          theme.tooltipTheme.textStyle?.fontFamilyFallback,
          AppTheme.fontFamilyFallback,
        );
      }
    });

    test('textTertiary and textSecondary meet WCAG AA on all surfaces', () {
      for (final colors in [AppColors.light, AppColors.dark]) {
        final surfaces = [
          colors.background,
          colors.surfaceMuted,
          colors.surfaceStrong,
          colors.elevatedSurface,
          colors.primarySoft,
        ];
        for (final surface in surfaces) {
          expect(
            _contrastRatio(colors.textTertiary, surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrastRatio(colors.textSecondary, surface),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    });
  });
}
