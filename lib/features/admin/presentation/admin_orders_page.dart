import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/download/download.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../campus/presentation/campus_providers.dart';
import '../../deposits/presentation/deposit_providers.dart';
import '../../textbooks/data/textbook_repository.dart';
import '../../textbooks/domain/order_filter.dart';
import '../../textbooks/domain/order_round.dart';
import '../../textbooks/domain/textbook.dart';
import '../../textbooks/domain/textbook_order.dart';
import '../../textbooks/presentation/round_deadline_form.dart';
import '../../textbooks/presentation/textbook_providers.dart';
import '../domain/csv_exports.dart';
import 'admin_order_providers.dart';
import 'admin_section_tabs.dart';
import 'admin_textbooks_page.dart';
import 'widgets/admin_order_widgets.dart';

/// 이 너비보다 좁으면 (모바일) 필터를 고정 너비 대신 폭에 맞춘다.
const _compactWidth = 600.0;

typedef _OrderRowFingerprint = ({
  OrderStatus status,
  bool isShipped,
  DateTime? receivedAt,
  String? receivedBy,
  String? confirmedDepositId,
  bool isAutoConfirmed,
});

_OrderRowFingerprint _fingerprint(TextbookOrder o) => (
  status: o.status,
  isShipped: o.isShipped,
  receivedAt: o.receivedAt,
  receivedBy: o.receivedBy,
  confirmedDepositId: o.confirmedDepositId,
  isAutoConfirmed: o.isAutoConfirmed,
);

bool _sameTargetSnapshots(
  List<TextbookOrder> before,
  List<TextbookOrder> after,
) {
  if (before.length != after.length) return false;
  final expected = {for (final o in before) o.id: _fingerprint(o)};
  if (expected.length != after.length) return false;
  for (final o in after) {
    if (expected[o.id] != _fingerprint(o)) return false;
  }
  return true;
}

class AdminOrdersPage extends ConsumerStatefulWidget {
  const AdminOrdersPage({super.key, this.tab});

  final String? tab;

  static const ordersTab = 'orders';
  static const catalogTab = 'catalog';

  static String normalizeTab(String? raw) =>
      raw == catalogTab ? catalogTab : ordersTab;

  @override
  ConsumerState<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends ConsumerState<AdminOrdersPage> {
  late String _tab = AdminOrdersPage.normalizeTab(widget.tab);

  /// 고른 회차 id. null 이면 이번 회차.
  String? _roundId;
  bool _allRounds = false;
  String? _textbookId;
  OrderStatus? _status;
  DeliveryStatus? _delivery;
  final _search = TextEditingController();
  final Set<String> _busy = {};
  bool _opRunning = false;

  /// 선택한 신청 id. 선택 막대에서 한 번에 처리한다.
  final Set<String> _picked = {};

  bool get _isBusy => _opRunning || _busy.isNotEmpty;

  OrderFilter get _currentFilter => OrderFilter(
    textbookId: _textbookId,
    status: _status,
    delivery: _delivery,
    query: _search.text,
  );

  @override
  void didUpdateWidget(covariant AdminOrdersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      _tab = AdminOrdersPage.normalizeTab(widget.tab);
    }
  }

  void _selectTab(String id) {
    if (_tab == id) return;
    setState(() => _tab = id);
    GoRouter.maybeOf(context)?.go(AppRoutes.adminOrdersTab(id));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 고른 회차. 전체 회차면 null. 고른 회차가 목록에 없으면(캠퍼스를 바꾼 경우) 이번 회차.
  OrderRound? _selected(RoundList rounds) {
    if (_allRounds) return null;
    return rounds.all.where((r) => r.id == _roundId).firstOrNull ??
        rounds.current;
  }

  Future<void> _setStatus(
    String? round,
    TextbookOrder order,
    OrderStatus status,
  ) async {
    if (_isBusy || order.status == status) return;
    setState(() {
      _opRunning = true;
      _busy.add(order.id);
    });
    try {
      final notifier = ref.read(adminOrdersProvider(round).notifier);
      final freshRows = await notifier.refetchFresh();
      if (!mounted) return;
      final freshOrder = freshRows.where((o) => o.id == order.id).firstOrNull;
      if (freshOrder == null || freshOrder.status != order.status) {
        showErrorSnack(context, const OrderStatusConflictException());
        return;
      }

      final needsConfirm =
          freshOrder.status == OrderStatus.paid ||
          status == OrderStatus.cancelled;
      if (needsConfirm) {
        final who = freshOrder.member?.name ?? '회원';
        final hasLinkedDeposit =
            freshOrder.isAutoConfirmed || freshOrder.confirmedDepositId != null;
        final depositNote =
            freshOrder.status == OrderStatus.paid && hasLinkedDeposit
            ? '\n연결된 입금 내역의 입금 연결 해제가 함께 처리됩니다.'
            : '';
        final title = status == OrderStatus.cancelled ? '신청 취소' : '입금확인 해제';
        final confirmLabel = status == OrderStatus.cancelled
            ? '신청 취소'
            : '${status.label}으로 변경';
        final ok = await showConfirmDialog(
          context,
          title: title,
          message:
              '$who님의 신청(${formatWon(freshOrder.totalPrice)})을 '
              '${freshOrder.status.label}에서 ${status.label} 상태로 변경합니다.$depositNote',
          confirmLabel: confirmLabel,
          destructive: true,
        );
        if (!ok || !mounted) return;

        final recheckedRows = await notifier.refetchFresh();
        if (!mounted) return;
        final currentOrder = recheckedRows
            .where((o) => o.id == freshOrder.id)
            .firstOrNull;
        if (currentOrder == null ||
            _fingerprint(currentOrder) != _fingerprint(freshOrder)) {
          showErrorSnack(context, const OrderStatusConflictException());
          return;
        }
      }

      await notifier.setStatus(freshOrder.id, status, from: freshOrder.status);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _opRunning = false;
          _busy.remove(order.id);
        });
      }
    }
  }

  Future<void> _setShipped(
    String? round,
    TextbookOrder order,
    bool shipped,
  ) async {
    if (_isBusy || order.isShipped == shipped) return;
    setState(() {
      _opRunning = true;
      _busy.add(order.id);
    });
    try {
      final notifier = ref.read(adminOrdersProvider(round).notifier);
      final freshRows = await notifier.refetchFresh();
      if (!mounted) return;
      final freshOrder = freshRows.where((o) => o.id == order.id).firstOrNull;
      if (freshOrder == null ||
          freshOrder.status != order.status ||
          freshOrder.isShipped != order.isShipped ||
          freshOrder.receivedAt != order.receivedAt ||
          freshOrder.receivedBy != order.receivedBy) {
        showErrorSnack(context, const OrderStatusConflictException());
        return;
      }

      // 회원이 이미 수령 확인한 건은 해제하면 수령 기록도 지워지므로 한 번 더 묻는다.
      if (!shipped && freshOrder.receivedAt != null) {
        final ok = await showConfirmDialog(
          context,
          title: '배송 해제',
          message:
              '${freshOrder.member?.name ?? '회원'}님이 이미 수령 확인한 신청입니다.\n'
              '배송을 해제하면 수령 기록도 함께 초기화됩니다.',
          confirmLabel: '배송 해제',
          destructive: true,
        );
        if (!ok || !mounted) return;

        final recheckedRows = await notifier.refetchFresh();
        if (!mounted) return;
        final currentOrder = recheckedRows
            .where((o) => o.id == freshOrder.id)
            .firstOrNull;
        if (currentOrder == null ||
            _fingerprint(currentOrder) != _fingerprint(freshOrder)) {
          showErrorSnack(context, const OrderStatusConflictException());
          return;
        }
      }

      await notifier.setShipped(
        freshOrder.id,
        shipped: shipped,
        expectedReceived: freshOrder.receivedAt != null,
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _opRunning = false;
          _busy.remove(order.id);
        });
      }
    }
  }

  Future<void> _setReceived(
    String? round,
    TextbookOrder order,
    bool received,
  ) async {
    if (_isBusy || (order.receivedAt != null) == received) return;
    setState(() {
      _opRunning = true;
      _busy.add(order.id);
    });
    try {
      final notifier = ref.read(adminOrdersProvider(round).notifier);
      final freshRows = await notifier.refetchFresh();
      if (!mounted) return;
      final freshOrder = freshRows.where((o) => o.id == order.id).firstOrNull;
      if (freshOrder == null ||
          freshOrder.status != order.status ||
          freshOrder.isShipped != order.isShipped ||
          freshOrder.receivedAt != order.receivedAt ||
          freshOrder.receivedBy != order.receivedBy) {
        showErrorSnack(context, const OrderStatusConflictException());
        return;
      }

      // 회원 본인이 확인한 기록을 지울 때만 한 번 더 묻는다.
      if (!received && !freshOrder.receivedByAdmin) {
        final ok = await showConfirmDialog(
          context,
          title: '수령 해제',
          message:
              '${freshOrder.member?.name ?? '회원'}님이 직접 수령 확인한 신청입니다.\n'
              '수령 기록을 지우시겠습니까?',
          confirmLabel: '수령 해제',
          destructive: true,
        );
        if (!ok || !mounted) return;

        final recheckedRows = await notifier.refetchFresh();
        if (!mounted) return;
        final currentOrder = recheckedRows
            .where((o) => o.id == freshOrder.id)
            .firstOrNull;
        if (currentOrder == null ||
            _fingerprint(currentOrder) != _fingerprint(freshOrder)) {
          showErrorSnack(context, const OrderStatusConflictException());
          return;
        }
      }

      await notifier.setReceived(freshOrder.id, received: received);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _opRunning = false;
          _busy.remove(order.id);
        });
      }
    }
  }

  /// 선택한 신청을 체크/해제한다. 최신 목록을 조회해 대상을 다시 계산한 뒤 확인받는다.
  Future<void> _bulk(String? round, OrderBulkField field, bool value) async {
    if (_isBusy) return;
    final pickedIds = Set<String>.of(_picked);
    if (pickedIds.isEmpty) return;
    final filter = _currentFilter;

    setState(() {
      _opRunning = true;
      _busy.addAll(pickedIds);
    });
    try {
      final notifier = ref.read(adminOrdersProvider(round).notifier);
      final freshRows = await notifier.refetchFresh();
      if (!mounted) return;

      List<TextbookOrder> computeTargets(List<TextbookOrder> rows) => filter
          .apply(rows)
          .where(
            (o) =>
                pickedIds.contains(o.id) &&
                field.isTarget(o) &&
                field.isChecked(o) != value,
          )
          .toList();

      final targets = computeTargets(freshRows);
      final action = '${field.label} ${value ? '체크' : '해제'}';
      if (targets.isEmpty) {
        showSnack(context, '선택한 신청 중 $action할 신청이 없습니다.');
        return;
      }

      // 해제하면 함께 지워지는 기록이나 입금 연결 해제를 알린다.
      final lostNote = switch ((field, value)) {
        (OrderBulkField.paid, false) => () {
          final linked = targets
              .where((o) => o.isAutoConfirmed || o.confirmedDepositId != null)
              .length;
          return linked == 0
              ? ''
              : '\n연결된 입금 $linked건의 입금 연결 해제가 함께 처리됩니다.';
        }(),
        (OrderBulkField.shipped, false) => () {
          final lost = targets.where((o) => o.receivedAt != null).length;
          return lost == 0 ? '' : '\n수령 기록 $lost건도 함께 초기화됩니다.';
        }(),
        (OrderBulkField.received, false) => () {
          final lost = targets.where((o) => !o.receivedByAdmin).length;
          return lost == 0 ? '' : '\n회원이 직접 확인한 기록 $lost건도 지워집니다.';
        }(),
        _ => '',
      };

      final ok = await showConfirmDialog(
        context,
        title: '$action (${targets.length}건)',
        message: '선택한 신청 중 ${targets.length}건을 $action합니다.$lostNote',
        confirmLabel: action,
        destructive: !value,
      );
      if (!ok || !mounted) return;

      final recheckedRows = await notifier.refetchFresh();
      if (!mounted) return;
      final recheckedTargets = computeTargets(recheckedRows);
      if (!_sameTargetSnapshots(targets, recheckedTargets)) {
        showErrorSnack(context, const OrderStatusConflictException());
        return;
      }

      final ids = [for (final o in recheckedTargets) o.id];
      await switch (field) {
        OrderBulkField.paid => notifier.bulkSetPaid(ids, paid: value),
        OrderBulkField.shipped => notifier.bulkSetShipped(ids, shipped: value),
        OrderBulkField.received => notifier.bulkSetReceived(
          ids,
          received: value,
        ),
      };
      if (mounted) showSnack(context, '${ids.length}건을 $action했습니다.');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _opRunning = false;
          _busy.removeAll(pickedIds);
        });
      }
    }
  }

  /// 선택한 신청을 각자 자기 회차의 이전([offset] = -1) / 다음(1) 회차로 옮긴다.
  Future<void> _shift(String? round, int offset) async {
    if (_isBusy) return;
    final pickedIds = Set<String>.of(_picked);
    if (pickedIds.isEmpty) return;
    final filter = _currentFilter;

    setState(() {
      _opRunning = true;
      _busy.addAll(pickedIds);
    });
    try {
      final notifier = ref.read(adminOrdersProvider(round).notifier);
      final freshRows = await notifier.refetchFresh();
      if (!mounted) return;

      List<TextbookOrder> computeTargets(List<TextbookOrder> rows) =>
          filter.apply(rows).where((o) => pickedIds.contains(o.id)).toList();

      final targets = computeTargets(freshRows);
      if (targets.isEmpty) {
        showSnack(context, '이동할 신청이 없습니다.');
        return;
      }

      final dir = offset < 0 ? '이전' : '다음';
      final ok = await showConfirmDialog(
        context,
        title: '$dir 회차로 이동 (${targets.length}건)',
        message:
            '선택한 ${targets.length}건을 각 신청의 $dir 회차로 옮깁니다.'
            '${offset > 0 ? '\n이번 회차의 다음 회차가 없으면 새로 만듭니다.' : ''}',
        confirmLabel: '$dir 회차로 이동',
      );
      if (!ok || !mounted) return;

      final recheckedRows = await notifier.refetchFresh();
      if (!mounted) return;
      final recheckedTargets = computeTargets(recheckedRows);
      if (!_sameTargetSnapshots(targets, recheckedTargets)) {
        showErrorSnack(context, const OrderStatusConflictException());
        return;
      }

      final ids = [for (final o in recheckedTargets) o.id];
      await ref.read(textbookRepositoryProvider).shiftOrders(ids, offset);
      // 옮긴 신청은 다른 회차 목록에 들어가고, 다음 회차가 새로 생겼을 수 있다.
      ref.invalidate(adminOrdersProvider);
      ref.invalidate(adminCurrentRoundProvider);
      ref.invalidate(adminRoundsProvider);
      ref.invalidate(unpaidLinkTargetsProvider);
      if (mounted) {
        setState(() => _picked.removeAll(ids));
        showSnack(context, '${ids.length}건을 $dir 회차로 옮겼습니다.');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _opRunning = false;
          _busy.removeAll(pickedIds);
        });
      }
    }
  }

  void _export(
    List<TextbookOrder> orders,
    OrderRound? selected, {
    required bool tally,
  }) {
    final round = selected == null ? '전체회차' : toDateOnly(selected.start);
    final name = tally ? '교재별집계' : '교재신청현황';
    try {
      downloadTextFile(
        safeFileName('${name}_${round}_${todayStamp()}.csv'),
        encodeCsv(
          tally ? textbookTallyCsvRows(orders) : textbookOrdersCsvRows(orders),
        ),
      );
    } catch (e) {
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(adminCampusIdProvider, (prev, next) {
      if (prev != next) {
        setState(() {
          _roundId = null;
          _textbookId = null;
          _picked.clear();
        });
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTabBar(
          maxWidth: 1200,
          selectedId: _tab,
          onSelected: _selectTab,
          tabs: const [
            AdminTabItem(id: AdminOrdersPage.ordersTab, label: '신청 현황'),
            AdminTabItem(id: AdminOrdersPage.catalogTab, label: '교재·카테고리'),
          ],
        ),
        Expanded(
          child: _tab == AdminOrdersPage.catalogTab
              ? const AdminTextbooksPage()
              : _buildOrdersBody(context),
        ),
      ],
    );
  }

  Widget _buildOrdersBody(BuildContext context) {
    final activeCampusId = ref.watch(adminCampusIdProvider);
    final campusFallback = missingCampusFallback(ref, activeCampusId);
    if (campusFallback != null) return campusFallback;

    final currentRoundAsync = ref.watch(adminCurrentRoundProvider);
    final roundList = ref.watch(adminRoundsProvider);
    final textbooks = ref.watch(textbooksProvider(CampusScope.admin));

    final currentRoundError =
        (currentRoundAsync.hasError && !currentRoundAsync.isLoading)
        ? currentRoundAsync.error
        : null;
    final roundsListError =
        (roundList.hasError && !roundList.isLoading) ? roundList.error : null;
    final roundReady =
        activeCampusId != null &&
        currentRoundAsync.hasUsableValue &&
        currentRoundAsync.requireValue != null;

    if (activeCampusId != null &&
        currentRoundAsync.hasUsableValue &&
        currentRoundAsync.requireValue == null) {
      return RefreshOverlay(
        refreshing: currentRoundAsync.isBackgroundRefreshing,
        child: const EmptyView(message: '신청 회차가 없습니다.'),
      );
    }

    final currentRound = roundReady ? currentRoundAsync.requireValue! : null;
    final roundsLoaded =
        roundReady &&
        roundList.hasValue &&
        !roundList.hasError &&
        roundList.requireValue?.campusId == activeCampusId;
    final RoundList? rounds = roundsLoaded ? roundList.requireValue! : null;

    final OrderRound? selected = _allRounds
        ? null
        : rounds != null
        ? _selected(rounds)
        : (_roundId == null || _roundId == currentRound?.id)
        ? currentRound
        : null;
    final String? roundId = _allRounds
        ? null
        : (rounds != null ? selected?.id : (_roundId ?? currentRound?.id));
    // 회차 목록을 불러오지 못한 상태에서 과거 회차를 선택 중이면 변경 작업을 잠근다.
    final selectionConfirmed =
        rounds != null ||
        _allRounds ||
        _roundId == null ||
        _roundId == currentRound?.id;
    final AsyncValue<List<TextbookOrder>>? orders = roundReady
        ? ref.watch(adminOrdersProvider(roundId))
        : null;
    final textbooksReady = activeCampusId != null && textbooks.hasUsableValue;
    final textbooksError = textbooks.hasError && !textbooks.isLoading;
    final books = textbooksReady ? textbooks.requireValue : const <Textbook>[];
    final filter = _currentFilter;

    final loaded = orders != null && orders.hasUsableValue
        ? orders.requireValue
        : null;
    final ordersLoading =
        currentRoundError == null &&
        (orders == null || (orders.isLoading && !orders.hasUsableValue));
    final ordersReady =
        orders != null &&
        orders.hasUsableValue &&
        !orders.isLoading &&
        !orders.isBackgroundRefreshing;
    final moneyControlsEnabled =
        activeCampusId != null &&
        roundReady &&
        !currentRoundAsync.isBackgroundRefreshing &&
        selectionConfirmed &&
        ordersReady &&
        !_isBusy;

    // 상태 칩과 배송 칩은 각각 자기 조건을 뺀 나머지 필터 기준으로 집계한다.
    final statusSummary = loaded == null
        ? null
        : summarizeByStatus(filter.withStatus(null).apply(loaded));
    final deliveryCounts = loaded == null
        ? null
        : countByDelivery(filter.withDelivery(null).apply(loaded));

    final refreshing =
        currentRoundAsync.isBackgroundRefreshing ||
        (roundList.isLoading &&
            roundList.hasValue &&
            !roundList.hasError &&
            roundList.value?.campusId == activeCampusId) ||
        textbooks.isBackgroundRefreshing ||
        (orders?.isBackgroundRefreshing ?? false);

    final Widget bodySection;
    if (currentRoundError != null) {
      bodySection = ErrorView(
        error: currentRoundError,
        onRetry: () {
          ref.invalidate(adminCurrentRoundProvider);
          ref.invalidate(adminRoundsProvider);
        },
      );
    } else if (orders == null) {
      bodySection = const _OrdersLoadingSection();
    } else {
      bodySection = AsyncValueView(
        value: orders,
        showRefreshIndicator: false,
        loading: const _OrdersLoadingSection(),
        onRetry: () => ref.invalidate(adminOrdersProvider(roundId)),
        data: (all) {
          final filtered = filter.apply(all);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextbookTallyAccordion(
                orders: filtered,
                textbookId: _textbookId,
              ),
              const SizedBox(height: 16),
              SectionTitle(
                '신청 ${filtered.length}건',
                trailing: _ExportMenu(
                  enabled: moneyControlsEnabled && filtered.isNotEmpty,
                  onExport: (tally) =>
                      _export(filtered, selected, tally: tally),
                ),
              ),
              if (filtered.isEmpty)
                const EmptyView(message: '조건에 맞는 신청이 없습니다.')
              else
                _OrdersList(
                  orders: filtered,
                  picked: _picked,
                  mutationsEnabled: moneyControlsEnabled,
                  onPick: (o, v) => setState(
                    () => v ? _picked.add(o.id) : _picked.remove(o.id),
                  ),
                  onPickAll: (v) => setState(() {
                    final ids = filtered.map((o) => o.id);
                    v ? _picked.addAll(ids) : _picked.removeAll(ids);
                  }),
                  onStatus: (o, s) => _setStatus(roundId, o, s),
                  onShipped: (o, v) => _setShipped(roundId, o, v),
                  onReceived: (o, v) => _setReceived(roundId, o, v),
                  onBulk: (f, v) => _bulk(roundId, f, v),
                  onShift: (offset) => _shift(roundId, offset),
                ),
            ],
          );
        },
      );
    }

    return RefreshOverlay(
      refreshing: refreshing,
      child: ListView(
        children: [
          PageBody(
            maxWidth: 1200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Filters(
                  rounds: rounds,
                  currentRound: currentRound,
                  selected: selected,
                  allRounds: _allRounds,
                  roundError: currentRoundError != null,
                  roundsListError:
                      roundsListError != null && currentRound != null,
                  deadlineEnabled: moneyControlsEnabled && currentRound != null,
                  onRetryRounds: () => ref.invalidate(adminRoundsProvider),
                  onRoundChanged: (r) => setState(() {
                    _allRounds = r == null;
                    if (r != null) _roundId = r.id;
                    _picked.clear();
                  }),
                  textbooks: books,
                  textbooksEnabled: textbooksReady || textbooksError,
                  textbooksError: textbooksError,
                  onRetryTextbooks: () => ref.invalidate(textbooksProvider),
                  textbookId: _textbookId,
                  onTextbookChanged: (v) => setState(() => _textbookId = v),
                  status: _status,
                  statusSummary: statusSummary,
                  statusLoading: ordersLoading,
                  onStatusChanged: (v) => setState(() => _status = v),
                  delivery: _delivery,
                  deliveryCounts: deliveryCounts,
                  onDeliveryChanged: (v) => setState(() => _delivery = v),
                  search: _search,
                  onSearchChanged: () => setState(() {}),
                ),
                const SizedBox(height: 16),
                bodySection,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.rounds,
    required this.currentRound,
    required this.selected,
    required this.allRounds,
    required this.roundError,
    required this.roundsListError,
    required this.deadlineEnabled,
    required this.onRetryRounds,
    required this.onRoundChanged,
    required this.textbooks,
    required this.textbooksEnabled,
    required this.textbooksError,
    required this.onRetryTextbooks,
    required this.textbookId,
    required this.onTextbookChanged,
    required this.status,
    required this.statusSummary,
    required this.statusLoading,
    required this.onStatusChanged,
    required this.delivery,
    required this.deliveryCounts,
    required this.onDeliveryChanged,
    required this.search,
    required this.onSearchChanged,
  });

  final RoundList? rounds;
  final OrderRound? currentRound;
  final OrderRound? selected;
  final bool allRounds;
  final bool roundError;
  final bool roundsListError;
  final bool deadlineEnabled;
  final VoidCallback onRetryRounds;
  final ValueChanged<OrderRound?> onRoundChanged;
  final List<Textbook> textbooks;
  final bool textbooksEnabled;
  final bool textbooksError;
  final VoidCallback onRetryTextbooks;
  final String? textbookId;
  final ValueChanged<String?> onTextbookChanged;
  final OrderStatus? status;
  final Map<OrderStatus, StatusSummary>? statusSummary;
  final bool statusLoading;
  final ValueChanged<OrderStatus?> onStatusChanged;
  final DeliveryStatus? delivery;

  /// 배송 상태별 건수 (취소 제외). 목록을 불러오는 중이면 null.
  final Map<DeliveryStatus, int>? deliveryCounts;
  final ValueChanged<DeliveryStatus?> onDeliveryChanged;
  final TextEditingController search;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 카드 없이 둔다. (입력칸이 회색 면이라 회색 카드와 겹치지 않게)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoundNavigator(
          rounds: rounds,
          currentRound: currentRound,
          selected: selected,
          allRounds: allRounds,
          roundError: roundError,
          deadlineEnabled: deadlineEnabled,
          onChanged: onRoundChanged,
        ),
        if (roundsListError) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: c.error),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '지난 회차 목록을 불러오지 못했습니다.',
                  style: TextStyle(fontSize: 13, color: c.error),
                ),
              ),
              TextButton(onPressed: onRetryRounds, child: const Text('다시 시도')),
            ],
          ),
        ],
        const SizedBox(height: 12),
        // 모바일에서는 고정 너비면 글자가 잘리므로 한 줄씩 꽉 채운다.
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < _compactWidth;
            double w(double desktop) =>
                compact ? constraints.maxWidth : desktop;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownMenu<String?>(
                  width: w(240),
                  enabled: textbooksEnabled,
                  label: const Text('교재'),
                  // 교재가 많으므로 입력해서 찾을 수 있게 한다.
                  enableFilter: true,
                  requestFocusOnTap: true,
                  initialSelection: textbookId,
                  onSelected: onTextbookChanged,
                  dropdownMenuEntries: [
                    const DropdownMenuEntry(value: null, label: '전체 교재'),
                    for (final t in textbooks)
                      DropdownMenuEntry(value: t.id, label: t.title),
                  ],
                ),
                SizedBox(
                  width: w(240),
                  child: TextField(
                    controller: search,
                    onChanged: (_) => onSearchChanged(),
                    decoration: InputDecoration(
                      labelText: '학번 / 이름 검색',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '지우기',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                search.clear();
                                onSearchChanged();
                              },
                            ),
                    ),
                  ),
                ),
                if (textbooksError)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 16, color: c.error),
                      const SizedBox(width: 6),
                      Text(
                        '교재 목록을 불러오지 못했습니다.',
                        style: TextStyle(fontSize: 13, color: c.error),
                      ),
                      TextButton(
                        onPressed: onRetryTextbooks,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        OrderStatusSummaryChips(
          status: status,
          summary: statusSummary,
          loading: statusLoading,
          onChanged: onStatusChanged,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('전체 배송'),
              selected: delivery == null,
              onSelected: (_) => onDeliveryChanged(null),
            ),
            for (final d in DeliveryStatus.values)
              ChoiceChip(
                label: Text(
                  deliveryCounts == null
                      ? d.label
                      : '${d.label} ${deliveryCounts![d]}',
                ),
                selected: delivery == d,
                onSelected: (_) => onDeliveryChanged(d),
              ),
          ],
        ),
      ],
    );
  }
}

/// 회차 이동: `< 회차 >`. 가운데를 누르면 달력에서 날짜를 골라 그 날짜의 회차로 간다.
class _RoundNavigator extends StatelessWidget {
  const _RoundNavigator({
    required this.rounds,
    required this.currentRound,
    required this.selected,
    required this.allRounds,
    required this.roundError,
    required this.deadlineEnabled,
    required this.onChanged,
  });

  final RoundList? rounds;
  final OrderRound? currentRound;

  /// null 이면 전체 회차.
  final OrderRound? selected;
  final bool allRounds;
  final bool roundError;
  final bool deadlineEnabled;

  /// null 이면 전체 회차.
  final ValueChanged<OrderRound?> onChanged;

  bool get _all => currentRound != null && allRounds;

  /// 최신순 목록에서 고른 회차의 위치
  int get _index => rounds == null || _all || selected == null
      ? 0
      : rounds!.all.indexWhere((r) => r.id == selected!.id);

  Future<void> _pickDate(BuildContext context) async {
    final r = rounds;
    if (r == null) return;
    final today = DateUtils.dateOnly(DateTime.now());
    final first = DateUtils.dateOnly(r.all.last.start);
    final initial = _all ? today : DateUtils.dateOnly(selected!.start);
    final picked = await showDatePicker(
      context: context,
      helpText: '날짜를 고르면 그 날짜의 회차로 이동합니다',
      initialDate: initial.isAfter(today)
          ? today
          : initial.isBefore(first)
          ? first
          : initial,
      firstDate: first.isAfter(today) ? today : first,
      // 앞으로의 날짜는 모두 이번 회차라 고를 필요가 없다.
      lastDate: today,
    );
    if (picked == null) return;
    // 오늘을 고르면 (오늘 시작하는 다음 회차가 있어도) 이번 회차로 간다.
    onChanged(
      DateUtils.isSameDay(picked, today)
          ? r.current
          : roundOnDate(r.all, picked),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    final r = rounds;
    final cur = currentRound;
    final index = _index;
    final isCurrent =
        cur != null && !_all && selected != null && selected!.id == cur.id;

    Widget centerContent;
    if (roundError) {
      centerContent = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          '회차 정보를 불러올 수 없습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: c.error),
        ),
      );
    } else if (cur == null) {
      centerContent = const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SkeletonRegion(
          child: Column(
            children: [
              SkeletonText(
                maxWidth: 140,
                fontSize: 16,
                alignment: Alignment.center,
                announce: false,
              ),
              SizedBox(height: 2),
              SkeletonText(
                maxWidth: 180,
                fontSize: 13,
                alignment: Alignment.center,
                announce: false,
              ),
            ],
          ),
        ),
      );
    } else {
      final title = _all ? '전체 회차' : (selected?.label ?? '선택한 회차');
      final sub = _all
          ? '모든 회차의 신청'
          : selected == null
          ? '회차 정보를 확인하지 못했습니다.'
          : isCurrent
          ? '이번 회차 · ${selected!.deadlineLabel} 마감'
          : r != null
          ? r.describe(selected!)
          : '이번 회차 · ${selected!.deadlineLabel} 마감';
      final inner = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (r != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 18,
                    color: c.textSecondary,
                  ),
                ],
              ],
            ),
            Text(sub, style: TextStyle(fontSize: 13, color: c.textSecondary)),
          ],
        ),
      );
      centerContent = r == null
          ? inner
          : Tooltip(
              message: '달력에서 회차 찾기',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _pickDate(context),
                child: inner,
              ),
            );
    }

    return Column(
      // stretch 면 아래 최대 너비가 무시된다.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Row(
            children: [
              IconButton(
                tooltip: '이전 회차',
                icon: const Icon(Icons.chevron_left),
                onPressed: r == null || _all || index >= r.all.length - 1
                    ? null
                    : () => onChanged(r.all[index + 1]),
              ),
              Expanded(child: centerContent),
              IconButton(
                tooltip: '다음 회차',
                icon: const Icon(Icons.chevron_right),
                // 미리 만든 다음 회차까지만 있다.
                onPressed: r == null || _all || index == 0
                    ? null
                    : () => onChanged(r.all[index - 1]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (cur != null && !isCurrent)
              ActionChip(
                avatar: const Icon(Icons.today, size: 18),
                label: const Text('이번 회차로'),
                onPressed: () => onChanged(r?.current ?? cur),
              ),
            FilterChip(
              label: const Text('전체 회차'),
              selected: _all,
              onSelected: cur == null
                  ? null
                  : (v) => onChanged(v ? null : (r?.current ?? cur)),
            ),
            ActionChip(
              avatar: const Icon(Icons.schedule, size: 18),
              label: const Text('마감 변경'),
              onPressed: !deadlineEnabled
                  ? null
                  : () => showRoundDeadlineDialog(context),
            ),
          ],
        ),
      ],
    );
  }
}

typedef _OnToggle = void Function(TextbookOrder order, bool value);

String _itemsText(TextbookOrder o) =>
    o.items.map((i) => '${i.title} ×${i.quantity}').join(', ');

class _OrdersList extends StatelessWidget {
  const _OrdersList({
    required this.orders,
    required this.picked,
    this.mutationsEnabled = true,
    required this.onPick,
    required this.onPickAll,
    required this.onStatus,
    required this.onShipped,
    required this.onReceived,
    required this.onBulk,
    required this.onShift,
  });

  final List<TextbookOrder> orders;
  final Set<String> picked;
  final bool mutationsEnabled;
  final _OnToggle onPick;
  final ValueChanged<bool> onPickAll;
  final OnOrderStatus onStatus;
  final _OnToggle onShipped;
  final _OnToggle onReceived;
  final OnOrderBulk onBulk;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final enabled = mutationsEnabled;
    return LayoutBuilder(
      builder: (context, constraints) {
        final table = constraints.maxWidth >= 760;
        final bar = OrderBulkActionBar(
          orders: orders,
          picked: picked,
          enabled: enabled,
          showPickAll: !table,
          onPickAll: onPickAll,
          onBulk: onBulk,
          onShift: onShift,
        );
        if (table) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              bar,
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      // 체크 열까지 가로 스크롤 없이 보이도록 열을 좁게 둔다.
                      columnSpacing: 12,
                      horizontalMargin: 16,
                      onSelectAll: enabled
                          ? (v) => onPickAll(v ?? false)
                          : null,
                      columns: const [
                        DataColumn(label: Text('회원')),
                        DataColumn(label: Text('교재')),
                        DataColumn(label: Text('금액'), numeric: true),
                        DataColumn(label: Text('상태')),
                        DataColumn(label: Text('신청일')),
                        DataColumn(label: Text('배송')),
                        DataColumn(label: Text('수령')),
                      ],
                      rows: [
                        for (final o in orders)
                          DataRow(
                            selected: picked.contains(o.id),
                            onSelectChanged: enabled
                                ? (v) => onPick(o, v ?? false)
                                : null,
                            cells: [
                              DataCell(_MemberCell(o.member)),
                              DataCell(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 180,
                                  ),
                                  child: Text(
                                    _itemsText(o),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text(formatWon(o.totalPrice))),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    OrderStatusMenu(
                                      order: o,
                                      enabled: enabled,
                                      onStatus: onStatus,
                                    ),
                                    if (o.isAutoConfirmed) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        '자동 확인',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: context.colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              DataCell(Text(formatShortDateTime(o.createdAt))),
                              DataCell(
                                _ShippedCheckbox(
                                  order: o,
                                  enabled: enabled,
                                  onShipped: onShipped,
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _ReceivedCheckbox(
                                      order: o,
                                      enabled: enabled,
                                      onReceived: onReceived,
                                    ),
                                    _ReceiptText(o),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar,
            for (final o in orders) ...[
              _OrderCard(
                order: o,
                enabled: enabled,
                picked: picked.contains(o.id),
                onPick: enabled ? onPick : null,
                onStatus: onStatus,
                onShipped: onShipped,
                onReceived: onReceived,
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

/// 표의 회원 칸: 이름 + 학번 두 줄. 긴 이름은 말줄임.
class _MemberCell extends StatelessWidget {
  const _MemberCell(this.member);

  final OrderMember? member;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 110),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            member?.name ?? '-',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            member?.studentId ?? '',
            style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.enabled,
    required this.picked,
    required this.onPick,
    required this.onStatus,
    required this.onShipped,
    required this.onReceived,
  });

  final TextbookOrder order;
  final bool enabled;
  final bool picked;
  final _OnToggle? onPick;
  final OnOrderStatus onStatus;
  final _OnToggle onShipped;
  final _OnToggle onReceived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MergeSemantics(
                  child: Semantics(
                    label: '${order.member?.name ?? '신청'} 선택',
                    child: Checkbox(
                      value: picked,
                      onChanged: onPick == null
                          ? null
                          : (v) => onPick!(order, v ?? false),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${order.member?.name ?? '-'}  ${order.member?.studentId ?? ''}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    OrderStatusMenu(
                      order: order,
                      enabled: enabled,
                      onStatus: onStatus,
                    ),
                    if (order.isAutoConfirmed)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          '자동 확인',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            // 체크박스 아래부터는 이름과 같은 줄에 맞춘다.
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  Text(_itemsText(order)),
                  const SizedBox(height: 4),
                  Text(
                    '${order.round?.label ?? '-'} 회차',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatWon(order.totalPrice)} · ${formatDateTime(order.createdAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Row(
                    children: [
                      Expanded(child: _ShippedText(order)),
                      const Text('배송'),
                      _ShippedCheckbox(
                        order: order,
                        enabled: enabled,
                        onShipped: onShipped,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _ReceiptText(order)),
                      const Text('수령'),
                      _ReceivedCheckbox(
                        order: order,
                        enabled: enabled,
                        onReceived: onReceived,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 배송 완료 체크. 취소된 신청은 배송할 수 없다. (서버 트리거가 강제)
class _ShippedCheckbox extends StatelessWidget {
  const _ShippedCheckbox({
    required this.order,
    required this.enabled,
    required this.onShipped,
  });

  final TextbookOrder order;
  final bool enabled;
  final _OnToggle onShipped;

  @override
  Widget build(BuildContext context) {
    final cancelled = order.status == OrderStatus.cancelled;
    final who = order.member?.name ?? '신청';
    final box = MergeSemantics(
      child: Semantics(
        label: '$who 배송',
        child: Checkbox(
          value: order.isShipped,
          onChanged: !enabled || cancelled
              ? null
              : (v) => onShipped(order, v == true),
        ),
      ),
    );
    final at = order.shippedAt;
    return at == null
        ? box
        : Tooltip(message: '배송 처리 ${formatDateTime(at)}', child: box);
  }
}

/// 수령 체크. 배송된 신청만 체크할 수 있다. (서버 RPC 가 강제)
class _ReceivedCheckbox extends StatelessWidget {
  const _ReceivedCheckbox({
    required this.order,
    required this.enabled,
    required this.onReceived,
  });

  final TextbookOrder order;
  final bool enabled;
  final _OnToggle onReceived;

  @override
  Widget build(BuildContext context) {
    final cancelled = order.status == OrderStatus.cancelled;
    final who = order.member?.name ?? '신청';
    return MergeSemantics(
      child: Semantics(
        label: '$who 수령',
        child: Checkbox(
          value: order.receivedAt != null,
          onChanged: !enabled || cancelled || !order.isShipped
              ? null
              : (v) => onReceived(order, v == true),
        ),
      ),
    );
  }
}

/// 수령 여부 / 시각 / 확인자. 배송 전이거나 취소된 신청은 `-`.
class _ReceiptText extends StatelessWidget {
  const _ReceiptText(this.order);

  final TextbookOrder order;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at = order.receivedAt;
    final text = order.status == OrderStatus.cancelled || !order.isShipped
        ? '-'
        : at == null
        ? '미수령'
        : [
            formatShortDateTime(at),
            if (order.receivedByAdmin) '관리자',
          ].join(' · ');
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: text == '-' ? c.textTertiary : c.textSecondary,
      ),
    );
  }
}

/// 배송 처리 시각. 배송 전이면 비운다.
class _ShippedText extends StatelessWidget {
  const _ShippedText(this.order);

  final TextbookOrder order;

  @override
  Widget build(BuildContext context) {
    final at = order.shippedAt;
    return Text(
      at == null ? '' : '배송 ${formatDateTime(at)}',
      style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
    );
  }
}

/// CSV 내보내기 메뉴. 현재 필터가 적용된 목록을 내보낸다.
class _ExportMenu extends StatelessWidget {
  const _ExportMenu({required this.enabled, required this.onExport});

  final bool enabled;
  final void Function(bool tally) onExport;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: !enabled
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.download),
        label: const Text('CSV 내보내기'),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: () => onExport(false),
          child: const Text('신청 목록 (필터 적용)'),
        ),
        MenuItemButton(
          onPressed: () => onExport(true),
          child: const Text('교재별 집계 (필터 적용)'),
        ),
      ],
    );
  }
}

class _OrdersLoadingSection extends StatelessWidget {
  const _OrdersLoadingSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TextbookTallyAccordion.loading(),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Text(
                '신청',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              const SkeletonBox(width: 32, height: 18),
              const Spacer(),
              _ExportMenu(enabled: false, onExport: (_) {}),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final table = constraints.maxWidth >= 760;
            if (table) {
              return SkeletonRegion(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: DataTable(
                        columnSpacing: 12,
                        horizontalMargin: 16,
                        columns: const [
                          DataColumn(label: Text('회원')),
                          DataColumn(label: Text('교재')),
                          DataColumn(label: Text('금액'), numeric: true),
                          DataColumn(label: Text('상태')),
                          DataColumn(label: Text('신청일')),
                          DataColumn(label: Text('배송')),
                          DataColumn(label: Text('수령')),
                        ],
                        rows: [
                          for (var i = 0; i < 4; i++)
                            DataRow(
                              cells: [
                                const DataCell(
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SkeletonBox(
                                        width: 56,
                                        height: 14,
                                        announce: false,
                                      ),
                                      SizedBox(height: 4),
                                      SkeletonBox(
                                        width: 68,
                                        height: 12,
                                        announce: false,
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  SkeletonBox(
                                    width: i.isEven ? 140 : 110,
                                    height: 14,
                                    announce: false,
                                  ),
                                ),
                                const DataCell(
                                  SkeletonBox(
                                    width: 64,
                                    height: 14,
                                    announce: false,
                                  ),
                                ),
                                const DataCell(
                                  SkeletonBox(
                                    width: 56,
                                    height: 22,
                                    announce: false,
                                  ),
                                ),
                                const DataCell(
                                  SkeletonBox(
                                    width: 72,
                                    height: 14,
                                    announce: false,
                                  ),
                                ),
                                const DataCell(
                                  SkeletonBox(
                                    width: 20,
                                    height: 20,
                                    announce: false,
                                  ),
                                ),
                                const DataCell(
                                  SkeletonBox(
                                    width: 20,
                                    height: 20,
                                    announce: false,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            return SkeletonList.cards(
              count: 3,
              spacing: 8,
              itemBuilder: (_, _) => const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SkeletonText(
                              maxWidth: 140,
                              fontSize: 16,
                              announce: false,
                            ),
                          ),
                          SkeletonBox(
                            width: 56,
                            height: 22,
                            announce: false,
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      SkeletonText(
                        maxWidth: 200,
                        fontSize: 14,
                        announce: false,
                      ),
                      SizedBox(height: 4),
                      SkeletonText(
                        maxWidth: 120,
                        fontSize: 13,
                        announce: false,
                      ),
                      SizedBox(height: 6),
                      SkeletonText(
                        maxWidth: 160,
                        fontSize: 13,
                        announce: false,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
