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
  /// 앱 시작 시 먼저 받는 Pretendard 기본 폰트 (KS X 1001 상용 2,350자 + 기호). pubspec.yaml 참고.
  static const fontFamily = 'Pretendard';

  /// 첫 화면 뒤 백그라운드에서 등록하는 확장 한글 폰트 (나머지 현대 한글 8,822자).
  static const extFontFamily = 'PretendardExt';

  /// 기본 폰트에 없는 드문 한글 음절을 확장 폰트로 이어서 그린다.
  static const fontFamilyFallback = [extFontFamily];

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primarySoft,
      onPrimaryContainer: c.primary,
      // 보조 / 3차 색도 파랑·회색에 묶어 다른 강조색이 생기지 않게 한다.
      secondary: c.textSecondary,
      onSecondary: c.background,
      secondaryContainer: c.surfaceMuted,
      onSecondaryContainer: c.textPrimary,
      tertiary: c.primary,
      onTertiary: c.onPrimary,
      tertiaryContainer: c.primarySoft,
      onTertiaryContainer: c.primary,
      error: c.error,
      onError: c.onError,
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
      outline: c.border,
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
      fontFamilyFallback: fontFamilyFallback,
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

    // 키보드로 이동할 때만 보이는 2px 포커스 테두리 (마우스 클릭 뒤에는 숨김).
    final focusSide = BorderSide(color: c.focusRing, width: 2);
    bool keyboardFocus(Set<WidgetState> s) =>
        s.contains(WidgetState.focused) &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    WidgetStateProperty<BorderSide?> focusBorder() =>
        WidgetStateProperty.resolveWith(
          (s) => keyboardFocus(s) ? focusSide : BorderSide.none,
        );

    return base.copyWith(
      textTheme: text,
      extensions: [c],
      materialTapTargetSize: MaterialTapTargetSize.padded,
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
        // 다이얼로그 / 카드 위에서도 입력칸 경계가 3:1 이상 보이도록.
        enabledBorder: OutlineInputBorder(
          borderRadius: rSm,
          borderSide: BorderSide(color: c.border),
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
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
      ),
      // 파란 CTA: 화면당 하나
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          // 비활성 컨트롤은 WCAG 대비 예외라 흐린 색을 그대로 쓴다.
          disabledBackgroundColor: c.surfaceStrong,
          disabledForegroundColor: c.textDisabled,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: rSm),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ).copyWith(side: focusBorder()),
      ),
      // 보조 버튼: 회색 면
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: c.surfaceMuted,
          foregroundColor: c.textPrimary,
          disabledForegroundColor: c.textDisabled,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: rSm),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ).copyWith(side: focusBorder()),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(borderRadius: rSm),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ).copyWith(side: focusBorder()),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
        ).copyWith(side: focusBorder()),
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
        side: WidgetStateBorderSide.resolveWith(
          (s) => keyboardFocus(s) ? focusSide : BorderSide.none,
        ),
        shape: const StadiumBorder(),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          fontWeight: FontWeight.w600,
          color: c.primary,
        ),
        // 라벨 20px + 위아래 12px = 높이 44px
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: states(Colors.white, c.border),
        trackColor: states(c.primary, c.surfaceStrong),
        trackOutlineColor: states(Colors.transparent, c.border),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: states(c.primary, Colors.transparent),
        checkColor: WidgetStateProperty.all(c.onPrimary),
        side: BorderSide(color: c.border, width: 1.5),
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
            fontFamilyFallback: fontFamilyFallback,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
          TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
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
          fontFamilyFallback: fontFamilyFallback,
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
          fontFamilyFallback: fontFamilyFallback,
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
    required this.textDisabled,
    required this.background,
    required this.surfaceMuted,
    required this.surfaceStrong,
    required this.elevatedSurface,
    required this.divider,
    required this.border,
    required this.focusRing,
    required this.onPrimary,
    required this.error,
    required this.onError,
    required this.errorSoft,
    required this.inverseSurface,
    required this.onInverseSurface,
  });

  static const light = AppColors(
    primary: Color(0xFF005AE6),
    primarySoft: Color(0xFFE8F3FF),
    textPrimary: Color(0xFF191F28),
    textSecondary: Color(0xFF4E5968),
    textTertiary: Color(0xFF5F6875),
    textDisabled: Color(0xFFB0B8C1),
    background: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF2F4F6),
    surfaceStrong: Color(0xFFE5E8EB),
    elevatedSurface: Color(0xFFFFFFFF),
    divider: Color(0xFFF2F4F6),
    border: Color(0xFF78828F),
    focusRing: Color(0xFF0B0F14),
    onPrimary: Color(0xFFFFFFFF),
    error: Color(0xFFC9202F),
    onError: Color(0xFFFFFFFF),
    errorSoft: Color(0xFFFFEEEE),
    inverseSurface: Color(0xFF191F28),
    onInverseSurface: Color(0xFFFFFFFF),
  );

  /// 어두운 배경에서는 #005AE6 글자가 읽기 어려워 같은 파랑을 밝게 쓴다.
  /// 밝은 파랑 면 위의 글자는 흰색이면 3.3:1 이라 어두운 [onPrimary] 를 쓴다.
  static const dark = AppColors(
    primary: Color(0xFF3D8BFF),
    primarySoft: Color(0xFF13203B),
    textPrimary: Color(0xFFECEEF1),
    textSecondary: Color(0xFF9AA4B2),
    textTertiary: Color(0xFF8D97A7),
    textDisabled: Color(0xFF5E6773),
    background: Color(0xFF111217),
    surfaceMuted: Color(0xFF1E2027),
    surfaceStrong: Color(0xFF2C2F38),
    elevatedSurface: Color(0xFF1E2027),
    divider: Color(0xFF24262E),
    border: Color(0xFF78828F),
    focusRing: Color(0xFFFFFFFF),
    onPrimary: Color(0xFF111217),
    error: Color(0xFFFF5C68),
    onError: Color(0xFF111217),
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

  /// 더 흐린 글자 (힌트, 흐린 배지, 선택 안 된 탭). 4.5:1 이상을 지킨다.
  final Color textTertiary;

  /// 비활성 컨트롤의 글자 / 장식. 대비 기준을 일부러 따르지 않으므로 읽어야 하는 글자에는 쓰지 않는다.
  final Color textDisabled;

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

  /// 입력칸 / 체크박스 / 스위치 경계. 흰 면과 회색 면 모두에서 3:1 이상.
  final Color border;

  /// 키보드 포커스 테두리. 면 색과 파랑 / 빨강 버튼 면 위에서 3:1 이상.
  final Color focusRing;

  /// [primary] 면 위의 글자
  final Color onPrimary;

  /// 오류 / 위험 동작에만 사용
  final Color error;

  /// [error] 면 위의 글자
  final Color onError;
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
    Color? textDisabled,
    Color? background,
    Color? surfaceMuted,
    Color? surfaceStrong,
    Color? elevatedSurface,
    Color? divider,
    Color? border,
    Color? focusRing,
    Color? onPrimary,
    Color? error,
    Color? onError,
    Color? errorSoft,
    Color? inverseSurface,
    Color? onInverseSurface,
  }) => AppColors(
    primary: primary ?? this.primary,
    primarySoft: primarySoft ?? this.primarySoft,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    textDisabled: textDisabled ?? this.textDisabled,
    background: background ?? this.background,
    surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    surfaceStrong: surfaceStrong ?? this.surfaceStrong,
    elevatedSurface: elevatedSurface ?? this.elevatedSurface,
    divider: divider ?? this.divider,
    border: border ?? this.border,
    focusRing: focusRing ?? this.focusRing,
    onPrimary: onPrimary ?? this.onPrimary,
    error: error ?? this.error,
    onError: onError ?? this.onError,
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
      textDisabled: l(textDisabled, other.textDisabled),
      background: l(background, other.background),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceStrong: l(surfaceStrong, other.surfaceStrong),
      elevatedSurface: l(elevatedSurface, other.elevatedSurface),
      divider: l(divider, other.divider),
      border: l(border, other.border),
      focusRing: l(focusRing, other.focusRing),
      onPrimary: l(onPrimary, other.onPrimary),
      error: l(error, other.error),
      onError: l(onError, other.onError),
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
