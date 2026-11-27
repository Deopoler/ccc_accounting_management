import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;

import '../../features/admin/presentation/admin_order_providers.dart';
import '../../features/admin/presentation/member_providers.dart';
import '../../features/campus/presentation/campus_providers.dart';
import '../../features/deposits/domain/bank_deposit.dart';
import '../../features/deposits/presentation/deposit_providers.dart';
import '../../features/events/presentation/event_providers.dart';
import '../../features/feedback/presentation/feedback_providers.dart';
import '../../features/settings/presentation/settings_providers.dart';
import '../../features/textbooks/presentation/textbook_providers.dart';
import 'routes.dart';

/// Silently refreshes already-loaded providers for [uri] on re-entry.
/// Skips providers still loading so first visits do not double-fetch.
void revalidateRoute(WidgetRef ref, Uri uri) {
  void refreshIfLoaded(ProviderBase<AsyncValue<Object?>> provider) {
    if (!ref.exists(provider)) return;
    final state = ref.read(provider);
    if (state.hasValue && !state.isLoading) {
      ref.invalidate(provider);
    }
  }

  final segments = uri.pathSegments;
  if (segments.length == 3 &&
      segments[0] == 'admin' &&
      segments[1] == 'events') {
    final eventId = segments[2];
    refreshIfLoaded(eventProvider(eventId));
    refreshIfLoaded(eventPaymentsProvider(eventId));
    refreshIfLoaded(membersProvider);
    return;
  }
  if (segments.length == 3 &&
      segments[0] == 'textbooks' &&
      segments[1] == 'complete') {
    refreshIfLoaded(orderProvider(segments[2]));
    return;
  }

  switch (uri.path) {
    case AppRoutes.home:
      refreshIfLoaded(myOrdersProvider);
      refreshIfLoaded(currentRoundProvider);
      refreshIfLoaded(eventsProvider(CampusScope.member));
      refreshIfLoaded(myEventPaymentsProvider);
    case AppRoutes.textbooks:
      refreshIfLoaded(textbooksProvider(CampusScope.member));
      refreshIfLoaded(textbookCategoriesProvider(CampusScope.member));
      refreshIfLoaded(currentRoundProvider);
      final editOrderId = uri.queryParameters['edit'];
      if (editOrderId != null && editOrderId.isNotEmpty) {
        refreshIfLoaded(orderProvider(editOrderId));
      }
    case AppRoutes.myOrders:
      refreshIfLoaded(myOrdersProvider);
      refreshIfLoaded(currentRoundProvider);
      refreshIfLoaded(bankAccountProvider(CampusScope.member));
    case AppRoutes.events:
      refreshIfLoaded(eventsProvider(CampusScope.member));
      refreshIfLoaded(myEventPaymentsProvider);
      refreshIfLoaded(bankAccountProvider(CampusScope.member));
    case AppRoutes.adminMembers:
      refreshIfLoaded(membersProvider);
    case AppRoutes.adminTextbooks:
      refreshIfLoaded(textbooksProvider(CampusScope.admin));
      refreshIfLoaded(textbookCategoriesProvider(CampusScope.admin));
    case AppRoutes.adminOrders:
      final rounds = ref.exists(adminRoundsProvider)
          ? ref.read(adminRoundsProvider).value
          : null;
      final current = ref.exists(adminCurrentRoundProvider)
          ? ref.read(adminCurrentRoundProvider).value
          : null;
      refreshIfLoaded(adminCurrentRoundProvider);
      refreshIfLoaded(adminRoundsProvider);
      refreshIfLoaded(textbooksProvider(CampusScope.admin));
      refreshIfLoaded(adminOrdersProvider(null));
      final refreshedRoundIds = <String>{};
      if (rounds != null) {
        for (final round in rounds.all) {
          if (refreshedRoundIds.add(round.id)) {
            refreshIfLoaded(adminOrdersProvider(round.id));
          }
        }
      }
      if (current != null && refreshedRoundIds.add(current.id)) {
        refreshIfLoaded(adminOrdersProvider(current.id));
      }
    case AppRoutes.adminEvents:
      refreshIfLoaded(eventsProvider(CampusScope.admin));
      refreshIfLoaded(eventSummariesProvider);
    case AppRoutes.adminDeposits:
      refreshIfLoaded(depositCountsProvider);
      for (final filter in DepositFilter.values) {
        refreshIfLoaded(bankDepositsProvider(filter));
      }
    case AppRoutes.adminSettings:
      refreshIfLoaded(bankAccountProvider(CampusScope.admin));
      refreshIfLoaded(adminCurrentRoundProvider);
      refreshIfLoaded(depositSettingsProvider);
    case AppRoutes.adminCampuses:
      refreshIfLoaded(campusesProvider);
    case AppRoutes.adminFeedback:
      for (final filter in FeedbackFilter.values) {
        refreshIfLoaded(feedbackListProvider(filter));
      }
  }
}
