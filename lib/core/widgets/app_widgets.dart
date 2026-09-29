import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// 배지 톤.
///   * [accent]  파랑: 해야 할 일 (미납, 입금 대기, 승인 대기)
///   * [neutral] 회색: 끝난 일 / 일반 정보 (완납, 입금확인)
///   * [muted]   흐린 회색: 비활성 (취소, 신청 불가, 대상 아님)
enum BadgeTone { accent, neutral, muted }

/// 작은 상태 배지. 색은 톤으로만 정한다.
class AppBadge extends StatelessWidget {
  const AppBadge(this.label, {super.key, this.tone = BadgeTone.neutral});

  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (tone) {
      BadgeTone.accent => (c.primarySoft, c.primary),
      BadgeTone.neutral => (c.surfaceStrong, c.textPrimary),
      BadgeTone.muted => (c.surfaceMuted, c.textTertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 금액 크기
enum AmountSize {
  /// 목록 안의 금액
  small(17),

  /// 카드의 대표 금액
  medium(22),

  /// 화면의 핵심 금액 (신청 완료 합계 등)
  large(28);

  const AmountSize(this.fontSize);

  final double fontSize;
}

/// 크고 굵은 금액. `1,000원`
class AmountText extends StatelessWidget {
  const AmountText(
    this.amount, {
    super.key,
    this.size = AmountSize.medium,
    this.highlight = false,
    this.textAlign,
  });

  final num amount;
  final AmountSize size;

  /// true 면 강조색(파랑). 내야 할 금액처럼 행동이 필요한 금액에만 쓴다.
  final bool highlight;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text(
      formatWon(amount),
      textAlign: textAlign,
      style: TextStyle(
        fontSize: size.fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.3,
        color: highlight ? c.primary : c.textPrimary,
      ),
    );
  }
}

/// 라벨 + 큰 값 (대시보드 / 요약용)
class LabeledValue extends StatelessWidget {
  const LabeledValue({super.key, required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
        ),
        const SizedBox(height: 4),
        value,
      ],
    );
  }
}

/// 큰 굵은 숫자 텍스트 (금액이 아닌 건수 등)
class FigureText extends StatelessWidget {
  const FigureText(this.text, {super.key, this.size = AmountSize.medium});

  final String text;
  final AmountSize size;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: size.fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.3,
        color: context.colors.textPrimary,
      ),
    );
  }
}
