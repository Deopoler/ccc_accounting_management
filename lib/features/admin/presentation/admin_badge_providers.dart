import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../campus/presentation/campus_providers.dart';
import '../../deposits/presentation/deposit_providers.dart';
import '../../feedback/presentation/feedback_providers.dart';
import 'member_providers.dart';

/// 가입 승인 대기 회원 수. 로딩/오류/0건/비관리자/캠퍼스 미결정이면 null.
final adminPendingMembersBadgeProvider = Provider.autoDispose<int?>((ref) {
  if (!ref.watch(isAdminProvider)) return null;
  if (ref.watch(adminCampusIdProvider) == null) return null;
  final members = ref.watch(membersProvider);
  if (!members.hasUsableValue) return null;
  final count = members.requireValue.where((m) => !m.isApproved).length;
  return count > 0 ? count : null;
});

/// 검토 필요 입금 건수. 로딩/오류/0건/비관리자/캠퍼스 미결정이면 null.
final adminDepositReviewBadgeProvider = Provider.autoDispose<int?>((ref) {
  if (!ref.watch(isAdminProvider)) return null;
  if (ref.watch(adminCampusIdProvider) == null) return null;
  final counts = ref.watch(depositCountsProvider);
  if (!counts.hasUsableValue) return null;
  final count = counts.requireValue.needsReview;
  return count > 0 ? count : null;
});

/// 미확인 피드백 건수 (총괄 관리자 전용). 로딩/오류/0건이면 null.
final adminUnresolvedFeedbackBadgeProvider = Provider.autoDispose<int?>((ref) {
  if (!ref.watch(isCentralAdminProvider)) return null;
  final list = ref.watch(feedbackListProvider(FeedbackFilter.unresolved));
  if (!list.hasUsableValue) return null;
  final count = list.requireValue.length;
  return count > 0 ? count : null;
});

/// 관리자 메뉴 경로에 대응하는 대기 작업 건수. 표시할 건수가 없으면 null.
final adminDestinationBadgeProvider = Provider.autoDispose
    .family<int?, String>((ref, path) => switch (path) {
      AppRoutes.adminMembers => ref.watch(adminPendingMembersBadgeProvider),
      AppRoutes.adminDeposits => ref.watch(adminDepositReviewBadgeProvider),
      AppRoutes.adminCentral => ref.watch(adminUnresolvedFeedbackBadgeProvider),
      _ => null,
    });

/// 관리자 네비게이션의 대기 작업 건수 배지.
class AdminCountBadge extends StatelessWidget {
  const AdminCountBadge({
    super.key,
    required this.count,
    this.selected = false,
  });

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = selected ? c.primary : c.primarySoft;
    final fg = selected ? c.onPrimary : c.primary;
    final display = count > 99 ? '99+' : '$count';

    return Semantics(
      label: '$count건 대기',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              display,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
