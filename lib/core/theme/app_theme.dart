import 'package:material_ui/material_ui.dart';

/// 디자인 원칙 (토스 스타일 참고, 자산은 사용하지 않음)
///
///   * 강조색은 파랑 하나. 파랑은 "해야 할 일 / 주요 행동"에만 쓴다.
///   * 빨강(error)은 오류와 삭제 같은 위험 동작에만 쓴다.
///   * 배경은 흰색, 카드·구분 영역은 옅은 회색. 그림자 대신 면 색으로 구분한다(플랫).
///   * 둥글기 12~16, 여백은 넉넉하게, 금액은 크고 굵게.
///   * 화면당 파란 버튼(FilledButton) 하나. 나머지는 회색(Outlined) / 글자(Text) 버튼.
///
/// 색·폰트·둥글기는 이 파일에서만 정한다. 화면에서는 [AppColors] / [AppRadius] 를 쓴다.
abstract final class AppTheme {
  /// 앱에 포함한 Pretendard (현대 한글 전체). pubspec.yaml 의 fonts 참고.
  static const fontFamily = 'Pretendard';

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: Colors.white,
      primaryContainer: c.primarySoft,
      onPrimaryContainer: c.primary,
      // 보조 / 3차 색도 파랑·회색에 묶어 다른 강조색이 생기지 않게 한다.
      secondary: c.textSecondary,
      onSecondary: c.background,
      secondaryContainer: c.surfaceMuted,
      onSecondaryContainer: c.textPrimary,
      tertiary: c.primary,
      onTertiary: Colors.white,
      tertiaryContainer: c.primarySoft,
      onTertiaryContainer: c.primary,
      error: c.error,
      onError: Colors.white,
      errorContainer: c.errorSoft,
      onErrorContainer: c.error,
      surface: c.background,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.background,
      surfaceContainer: c.surfaceMuted,
      surfaceContainerHigh: c.surfaceMuted,
      surfaceContainerHighest: c.surfaceStrong,
      outline: c.textTertiary,
      outlineVariant: c.divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: c.inverseSurface,
      onInverseSurface: c.onInverseSurface,
      inversePrimary: c.primarySoft,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
    );
    final text = base.textTheme
        .apply(bodyColor: c.textPrimary, displayColor: c.textPrimary)
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
          bodySmall: base.textTheme.bodySmall?.copyWith(color: c.textSecondary),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        );

    final rSm = BorderRadius.circular(AppRadius.sm);
    final rLg = BorderRadius.circular(AppRadius.lg);
    WidgetStateProperty<T> states<T>(T selected, T other) =>
        WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? selected : other,
        );

    return base.copyWith(
      textTheme: text,
      extensions: [c],
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 20),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: c.surfaceMuted,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: rLg),
      ),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceMuted,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: rSm,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: rSm,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: rSm,
          borderSide: BorderSide(color: c.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: rSm,
          borderSide: BorderSide(color: c.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: rSm,
          borderSide: BorderSide(color: c.error, width: 1.5),
        ),
        labelStyle: TextStyle(color: c.textSecondary),
        floatingLabelStyle: TextStyle(color: c.textSecondary),
        hintStyle: TextStyle(color: c.textTertiary),
        helperStyle: TextStyle(color: c.textSecondary),
        prefixIconColor: c.textTertiary,
        suffixIconColor: c.textTertiary,
      ),
      // 파란 CTA: 화면당 하나
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: c.surfaceStrong,
          disabledForegroundColor: c.textTertiary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: rSm),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      // 보조 버튼: 회색 면
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: c.surfaceMuted,
          foregroundColor: c.textPrimary,
          disabledForegroundColor: c.textTertiary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: rSm),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          shape: RoundedRectangleBorder(borderRadius: rSm),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.textSecondary),
      ),
      iconTheme: IconThemeData(color: c.textSecondary),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        selectedColor: c.textPrimary,
        selectedTileColor: c.surfaceMuted,
        subtitleTextStyle: text.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: rSm),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceMuted,
        selectedColor: c.primarySoft,
        disabledColor: c.surfaceMuted,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          color: c.primary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: states(c.primary, c.surfaceStrong),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: states(c.primary, Colors.transparent),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: BorderSide(color: c.textTertiary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceStrong,
        circularTrackColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: Colors.transparent,
        iconTheme: states(
          IconThemeData(color: c.textPrimary),
          IconThemeData(color: c.textTertiary),
        ),
        labelTextStyle: states(
          TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
          TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.textTertiary,
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: rSm,
          side: BorderSide(color: c.divider),
        ),
        textStyle: text.bodyLarge,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(c.elevatedSurface),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          elevation: WidgetStateProperty.all(2),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: rSm,
              side: BorderSide(color: c.divider),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(c.elevatedSurface),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: rSm,
              side: BorderSide(color: c.divider),
            ),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: rLg),
        titleTextStyle: text.titleLarge,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: rLg),
        headerBackgroundColor: c.elevatedSurface,
        headerForegroundColor: c.textPrimary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.inverseSurface,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: c.onInverseSurface,
          fontSize: 15,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: rSm),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: text.labelLarge?.copyWith(color: c.textSecondary),
        dataTextStyle: text.bodyMedium,
        dividerThickness: 1,
        headingRowColor: WidgetStateProperty.all(Colors.transparent),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          color: c.onInverseSurface,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// 둥글기
abstract final class AppRadius {
  /// 입력칸, 버튼, 작은 카드
  static const double sm = 12;

  /// 카드, 다이얼로그
  static const double lg = 16;
}

/// 색 토큰. 라이트 / 다크 짝으로 관리한다. 화면에서는 `context.colors` 로 쓴다.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primarySoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.background,
    required this.surfaceMuted,
    required this.surfaceStrong,
    required this.elevatedSurface,
    required this.divider,
    required this.error,
    required this.errorSoft,
    required this.inverseSurface,
    required this.onInverseSurface,
  });

  static const light = AppColors(
    primary: Color(0xFF0064FF),
    primarySoft: Color(0xFFE8F3FF),
    textPrimary: Color(0xFF191F28),
    textSecondary: Color(0xFF8B95A1),
    textTertiary: Color(0xFFB0B8C1),
    background: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF2F4F6),
    surfaceStrong: Color(0xFFE5E8EB),
    elevatedSurface: Color(0xFFFFFFFF),
    divider: Color(0xFFF2F4F6),
    error: Color(0xFFF04452),
    errorSoft: Color(0xFFFFEEEE),
    inverseSurface: Color(0xFF191F28),
    onInverseSurface: Color(0xFFFFFFFF),
  );

  /// 어두운 배경에서는 #0064FF 글자가 읽기 어려워 같은 파랑을 밝게 쓴다.
  static const dark = AppColors(
    primary: Color(0xFF3D8BFF),
    primarySoft: Color(0xFF17294A),
    textPrimary: Color(0xFFECEEF1),
    textSecondary: Color(0xFF8B95A1),
    textTertiary: Color(0xFF5E6773),
    background: Color(0xFF111217),
    surfaceMuted: Color(0xFF1E2027),
    surfaceStrong: Color(0xFF2C2F38),
    elevatedSurface: Color(0xFF1E2027),
    divider: Color(0xFF24262E),
    error: Color(0xFFFF6B75),
    errorSoft: Color(0xFF3A1D22),
    inverseSurface: Color(0xFFECEEF1),
    onInverseSurface: Color(0xFF111217),
  );

  /// 강조색 (주요 행동, 해야 할 일)
  final Color primary;

  /// 강조색 옅은 배경 (배지, 선택된 칩, 안내 박스)
  final Color primarySoft;

  /// 본문 글자
  final Color textPrimary;

  /// 보조 글자
  final Color textSecondary;

  /// 더 흐린 글자 (힌트, 비활성)
  final Color textTertiary;

  /// 화면 배경
  final Color background;

  /// 카드 / 구분 영역 / 입력칸
  final Color surfaceMuted;

  /// 회색 면 위의 한 단계 진한 회색 (비활성 버튼, 스위치 꺼짐, 진행 막대 바탕)
  final Color surfaceStrong;

  /// 다이얼로그 / 메뉴처럼 떠 있는 면
  final Color elevatedSurface;

  /// 구분선
  final Color divider;

  /// 오류 / 위험 동작에만 사용
  final Color error;
  final Color errorSoft;

  /// 스낵바 / 툴팁
  final Color inverseSurface;
  final Color onInverseSurface;

  @override
  AppColors copyWith({
    Color? primary,
    Color? primarySoft,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? background,
    Color? surfaceMuted,
    Color? surfaceStrong,
    Color? elevatedSurface,
    Color? divider,
    Color? error,
    Color? errorSoft,
    Color? inverseSurface,
    Color? onInverseSurface,
  }) => AppColors(
    primary: primary ?? this.primary,
    primarySoft: primarySoft ?? this.primarySoft,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    background: background ?? this.background,
    surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    surfaceStrong: surfaceStrong ?? this.surfaceStrong,
    elevatedSurface: elevatedSurface ?? this.elevatedSurface,
    divider: divider ?? this.divider,
    error: error ?? this.error,
    errorSoft: errorSoft ?? this.errorSoft,
    inverseSurface: inverseSurface ?? this.inverseSurface,
    onInverseSurface: onInverseSurface ?? this.onInverseSurface,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      primary: l(primary, other.primary),
      primarySoft: l(primarySoft, other.primarySoft),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      background: l(background, other.background),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceStrong: l(surfaceStrong, other.surfaceStrong),
      elevatedSurface: l(elevatedSurface, other.elevatedSurface),
      divider: l(divider, other.divider),
      error: l(error, other.error),
      errorSoft: l(errorSoft, other.errorSoft),
      inverseSurface: l(inverseSurface, other.inverseSurface),
      onInverseSurface: l(onInverseSurface, other.onInverseSurface),
    );
  }
}

extension AppThemeContext on BuildContext {
  /// 현재 테마의 색 토큰
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
