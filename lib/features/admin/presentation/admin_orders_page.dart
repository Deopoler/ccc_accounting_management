import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/download/download.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../textbooks/domain/order_filter.dart';
import '../../textbooks/domain/order_round.dart';
import '../../textbooks/domain/textbook.dart';
import '../../textbooks/domain/textbook_order.dart';
import '../../textbooks/presentation/textbook_providers.dart';
import '../../textbooks/presentation/widgets/order_widgets.dart';
import '../domain/csv_exports.dart';
import 'admin_order_providers.dart';
import '../../campus/presentation/campus_providers.dart';

/// 이 너비보다 좁으면 (모바일) 필터 / 집계 카드를 고정 너비 대신 폭에 맞춘다.
const _compactWidth = 600.0;

class AdminOrdersPage extends ConsumerStatefulWidget {
  const AdminOrdersPage({super.key});

  @override
  ConsumerState<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends ConsumerState<AdminOrdersPage> {
  /// 고른 회차 id. null 이면 이번 회차.
  String? _roundId;
  bool _allRounds = false;
  String? _textbookId;
  OrderStatus? _status;
  DeliveryStatus? _delivery;
  final _search = TextEditingController();
  final Set<String> _busy = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 고른 회차. 전체 회차면 null. 고른 회차가 목록에 없으면(캠퍼스를 바꾼 경우) 이번 회차.
  OrderRound? _selected(List<OrderRound> rounds) {
    if (_allRounds) return null;
    return rounds.where((r) => r.id == _roundId).firstOrNull ?? rounds.first;
  }

  Future<void> _setStatus(
    String? round,
    TextbookOrder order,
    OrderStatus status,
  ) async {
    if (order.status == status) return;
    setState(() => _busy.add(order.id));
    try {
      await ref
          .read(adminOrdersProvider(round).notifier)
          .setStatus(order.id, status);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(order.id));
    }
  }

  Future<void> _setShipped(
    String? round,
    TextbookOrder order,
    bool shipped,
  ) async {
    if (order.isShipped == shipped) return;
    // 회원이 이미 수령 확인한 건은 해제하면 수령 기록도 지워지므로 한 번 더 묻는다.
    if (!shipped && order.receivedAt != null) {
      final ok = await showConfirmDialog(
        context,
        title: '배송 해제',
        message:
            '${order.member?.name ?? '회원'}님이 이미 수령 확인한 신청입니다.\n'
            '배송을 해제하면 수령 기록도 함께 초기화됩니다.',
        confirmLabel: '배송 해제',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy.add(order.id));
    try {
      await ref
          .read(adminOrdersProvider(round).notifier)
          .setShipped(order.id, shipped: shipped);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(order.id));
    }
  }

  Future<void> _setReceived(
    String? round,
    TextbookOrder order,
    bool received,
  ) async {
    if ((order.receivedAt != null) == received) return;
    // 회원 본인이 확인한 기록을 지울 때만 한 번 더 묻는다.
    if (!received && !order.receivedByAdmin) {
      final ok = await showConfirmDialog(
        context,
        title: '수령 해제',
        message:
            '${order.member?.name ?? '회원'}님이 직접 수령 확인한 신청입니다.\n'
            '수령 기록을 지우시겠습니까?',
        confirmLabel: '수령 해제',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy.add(order.id));
    try {
      await ref
          .read(adminOrdersProvider(round).notifier)
          .setReceived(order.id, received: received);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(order.id));
    }
  }

  /// 현재 목록(필터 적용)의 대상 전체를 체크/해제한다. 건수를 보여 주고 확인받는다.
  Future<void> _bulk(
    String? round,
    List<TextbookOrder> orders,
    _BulkField field,
    bool value,
  ) async {
    final targets = orders
        .where((o) => field.isTarget(o) && field.isChecked(o) != value)
        .toList();
    if (targets.isEmpty) return;

    // 해제하면 함께 지워지는 기록을 알린다.
    final lost = switch ((field, value)) {
      (_BulkField.shipped, false) =>
        targets.where((o) => o.receivedAt != null).length,
      (_BulkField.received, false) =>
        targets.where((o) => !o.receivedByAdmin).length,
      _ => 0,
    };
    final lostNote = lost == 0
        ? ''
        : field == _BulkField.shipped
        ? '\n수령 기록 $lost건도 함께 초기화됩니다.'
        : '\n회원이 직접 확인한 기록 $lost건도 지워집니다.';
    final action = '${field.label} ${value ? '체크' : '해제'}';

    final ok = await showConfirmDialog(
      context,
      title: '$action (${targets.length}건)',
      message: '현재 목록에서 ${targets.length}건을 $action합니다.$lostNote',
      confirmLabel: action,
      destructive: !value,
    );
    if (!ok || !mounted) return;

    final ids = [for (final o in targets) o.id];
    final notifier = ref.read(adminOrdersProvider(round).notifier);
    setState(() => _busy.addAll(ids));
    try {
      await switch (field) {
        _BulkField.paid => notifier.bulkSetPaid(ids, paid: value),
        _BulkField.shipped => notifier.bulkSetShipped(ids, shipped: value),
        _BulkField.received => notifier.bulkSetReceived(ids, received: value),
      };
      if (mounted) showSnack(context, '${ids.length}건을 $action했습니다.');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.removeAll(ids));
    }
  }

  Future<void> _move(
    String? round,
    List<OrderRound> rounds,
    TextbookOrder order,
  ) async {
    final target = await showDialog<OrderRound>(
      context: context,
      builder: (_) => _MoveRoundDialog(order: order, rounds: rounds),
    );
    if (target == null || target.id == order.roundId || !mounted) return;
    setState(() => _busy.add(order.id));
    try {
      await ref
          .read(adminOrdersProvider(round).notifier)
          .moveOrder(order.id, target);
      // 옮긴 회차 / 전체 회차 목록도 다시 불러오게 한다.
      ref.invalidate(adminOrdersProvider(target.id));
      if (round != null) ref.invalidate(adminOrdersProvider(null));
      if (mounted) {
        showSnack(
          context,
          '${order.member?.name ?? '신청'}님의 신청을 ${target.label} 회차로 옮겼습니다.',
        );
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(order.id));
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
    final roundList = ref.watch(adminRoundsProvider);
    final textbooks = ref.watch(textbooksProvider(CampusScope.admin));

    if (roundList.hasError) {
      return ErrorView(
        error: roundList.error!,
        onRetry: () => ref.invalidate(adminRoundsProvider),
      );
    }
    if (!roundList.hasValue) return const LoadingView();

    final rounds = roundList.requireValue;
    if (rounds.isEmpty) return const EmptyView(message: '신청 회차가 없습니다.');
    final selected = _selected(rounds);
    final roundId = selected?.id;
    final orders = ref.watch(adminOrdersProvider(roundId));
    final books = textbooks.value ?? const <Textbook>[];
    final filter = OrderFilter(
      textbookId: _textbookId,
      status: _status,
      delivery: _delivery,
      query: _search.text,
    );
    // 배송 칩의 건수는 배송 조건을 뺀 나머지 필터 기준으로 센다.
    final loaded = orders.value;
    final deliveryCounts = loaded == null
        ? null
        : countByDelivery(filter.withDelivery(null).apply(loaded));

    return ListView(
      children: [
        PageBody(
          maxWidth: 1200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Filters(
                rounds: rounds,
                selected: selected,
                onRoundChanged: (r) => setState(() {
                  _allRounds = r == null;
                  if (r != null) _roundId = r.id;
                }),
                textbooks: books,
                textbookId: _textbookId,
                onTextbookChanged: (v) => setState(() => _textbookId = v),
                status: _status,
                onStatusChanged: (v) => setState(() => _status = v),
                delivery: _delivery,
                deliveryCounts: deliveryCounts,
                onDeliveryChanged: (v) => setState(() => _delivery = v),
                search: _search,
                onSearchChanged: () => setState(() {}),
              ),
              const SizedBox(height: 16),
              AsyncValueView(
                value: orders,
                onRetry: () => ref.invalidate(adminOrdersProvider(roundId)),
                data: (all) {
                  final filtered = filter.apply(all);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Summary(orders: filtered, textbookId: _textbookId),
                      const SizedBox(height: 16),
                      SectionTitle(
                        '신청 ${filtered.length}건',
                        trailing: _ExportMenu(
                          enabled: filtered.isNotEmpty,
                          onExport: (tally) =>
                              _export(filtered, selected, tally: tally),
                        ),
                      ),
                      if (filtered.isEmpty)
                        const EmptyView(message: '조건에 맞는 신청이 없습니다.')
                      else
                        _OrdersList(
                          orders: filtered,
                          busy: _busy,
                          onStatus: (o, s) => _setStatus(roundId, o, s),
                          onShipped: (o, v) => _setShipped(roundId, o, v),
                          onReceived: (o, v) => _setReceived(roundId, o, v),
                          onMove: (o) => _move(roundId, rounds, o),
                          onBulk: (f, v) => _bulk(roundId, filtered, f, v),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// 필터
// ----------------------------------------------------------------------------

class _Filters extends StatelessWidget {
  const _Filters({
    required this.rounds,
    required this.selected,
    required this.onRoundChanged,
    required this.textbooks,
    required this.textbookId,
    required this.onTextbookChanged,
    required this.status,
    required this.onStatusChanged,
    required this.delivery,
    required this.deliveryCounts,
    required this.onDeliveryChanged,
    required this.search,
    required this.onSearchChanged,
  });

  final List<OrderRound> rounds;
  final OrderRound? selected;
  final ValueChanged<OrderRound?> onRoundChanged;
  final List<Textbook> textbooks;
  final String? textbookId;
  final ValueChanged<String?> onTextbookChanged;
  final OrderStatus? status;
  final ValueChanged<OrderStatus?> onStatusChanged;
  final DeliveryStatus? delivery;

  /// 배송 상태별 건수 (취소 제외). 목록을 불러오는 중이면 null.
  final Map<DeliveryStatus, int>? deliveryCounts;
  final ValueChanged<DeliveryStatus?> onDeliveryChanged;
  final TextEditingController search;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    // 카드 없이 둔다. (입력칸이 회색 면이라 회색 카드와 겹치지 않게)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoundNavigator(
          rounds: rounds,
          selected: selected,
          onChanged: onRoundChanged,
        ),
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
              children: [
                DropdownMenu<String?>(
                  width: w(240),
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
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('전체 상태'),
              selected: status == null,
              onSelected: (_) => onStatusChanged(null),
            ),
            for (final s in OrderStatus.values)
              ChoiceChip(
                label: Text(s.label),
                selected: status == s,
                onSelected: (_) => onStatusChanged(s),
              ),
          ],
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
    required this.selected,
    required this.onChanged,
  });

  /// 최신순. 첫 번째가 이번 회차.
  final List<OrderRound> rounds;

  /// null 이면 전체 회차.
  final OrderRound? selected;

  /// null 이면 전체 회차.
  final ValueChanged<OrderRound?> onChanged;

  bool get _all => selected == null;

  /// 0 = 이번 회차, n = n회차 전
  int get _index => _all ? 0 : rounds.indexWhere((r) => r.id == selected!.id);

  Future<void> _pickDate(BuildContext context) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final first = DateUtils.dateOnly(rounds.last.start);
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
    if (picked != null) onChanged(roundOnDate(rounds, picked));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    final index = _index;
    final title = _all ? '전체 회차' : selected!.label;
    final sub = _all
        ? '모든 회차의 신청'
        : index == 0
        ? '이번 회차 · ${selected!.deadlineLabel} 마감'
        : '$index회차 전';

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
                onPressed: _all || index >= rounds.length - 1
                    ? null
                    : () => onChanged(rounds[index + 1]),
              ),
              Expanded(
                child: Tooltip(
                  message: '달력에서 회차 찾기',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _pickDate(context),
                    child: Padding(
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
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.calendar_month_outlined,
                                size: 18,
                                color: c.textSecondary,
                              ),
                            ],
                          ),
                          Text(
                            sub,
                            style: TextStyle(
                              fontSize: 13,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '다음 회차',
                icon: const Icon(Icons.chevron_right),
                // 이번 회차보다 뒤는 없다.
                onPressed: _all || index == 0
                    ? null
                    : () => onChanged(rounds[index - 1]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (index != 0)
              ActionChip(
                avatar: const Icon(Icons.today, size: 18),
                label: const Text('이번 회차로'),
                onPressed: () => onChanged(rounds.first),
              ),
            FilterChip(
              label: const Text('전체 회차'),
              selected: _all,
              onSelected: (v) => onChanged(v ? null : rounds.first),
            ),
          ],
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// 집계
// ----------------------------------------------------------------------------

class _Summary extends StatelessWidget {
  const _Summary({required this.orders, required this.textbookId});

  final List<TextbookOrder> orders;
  final String? textbookId;

  @override
  Widget build(BuildContext context) {
    final byStatus = summarizeByStatus(orders);
    final tallies =
        tallyByTextbook(orders).entries
            .where((e) => textbookId == null || e.key == textbookId)
            .map((e) => e.value)
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    final totalQty = tallies.fold(0, (s, t) => s + t.quantity);
    final totalAmount = tallies.fold(0, (s, t) => s + t.amount);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              for (final s in OrderStatus.values)
                _StatCard(
                  label: s.label,
                  value: '${byStatus[s]!.count}건',
                  sub: formatWon(byStatus[s]!.amount),
                  compact: constraints.maxWidth < _compactWidth,
                ),
            ];
            // 모바일에서는 고정 너비 카드가 한 줄에 하나씩 떨어지므로 한 줄에 나눠 담는다.
            if (constraints.maxWidth < _compactWidth) {
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            }
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards) SizedBox(width: 180, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('교재별 집계 (취소 제외)'),
                if (tallies.isEmpty)
                  Text('집계할 신청이 없습니다.', style: theme.textTheme.bodyMedium)
                else
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(),
                      1: IntrinsicColumnWidth(),
                      2: IntrinsicColumnWidth(),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      _tallyRow(context, '교재', '수량', '금액', header: true),
                      for (final t in tallies)
                        _tallyRow(
                          context,
                          t.title,
                          '${t.quantity}권',
                          formatWon(t.amount),
                        ),
                      _tallyRow(
                        context,
                        '합계',
                        '$totalQty권',
                        formatWon(totalAmount),
                        header: true,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  TableRow _tallyRow(
    BuildContext context,
    String a,
    String b,
    String c, {
    bool header = false,
  }) {
    final style = header
        ? Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;
    Widget cell(String text, {bool right = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Text(
        text,
        style: style,
        textAlign: right ? TextAlign.right : TextAlign.left,
      ),
    );
    return TableRow(
      // 카드(회색 면) 안의 표라 머리행은 면 대신 구분선으로 나눈다.
      decoration: header
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.colors.surfaceStrong),
              ),
            )
          : null,
      children: [cell(a), cell(b, right: true), cell(c, right: true)],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    this.compact = false,
  });

  final String label;
  final String value;
  final String sub;

  /// 좁은 카드: 여백을 줄이고, 큰 금액은 넘치지 않게 글자를 줄인다.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget fit(Widget child) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: child,
    );
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: c.textSecondary)),
            const SizedBox(height: 6),
            fit(FigureText(value)),
            const SizedBox(height: 2),
            fit(
              Text(sub, style: TextStyle(fontSize: 14, color: c.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 목록 (데스크톱: 표 / 모바일: 카드)
// ----------------------------------------------------------------------------

typedef _OnStatus = void Function(TextbookOrder order, OrderStatus status);
typedef _OnToggle = void Function(TextbookOrder order, bool value);
typedef _OnMove = void Function(TextbookOrder order);
typedef _OnBulk = void Function(_BulkField field, bool value);

/// 전체 체크할 수 있는 항목. 취소된 신청은 모두 대상이 아니다.
enum _BulkField {
  paid('입금확인'),
  shipped('배송'),
  received('수령');

  const _BulkField(this.label);

  final String label;

  bool isTarget(TextbookOrder o) =>
      o.status != OrderStatus.cancelled &&
      (this != _BulkField.received || o.isShipped);

  bool isChecked(TextbookOrder o) => switch (this) {
    _BulkField.paid => o.status == OrderStatus.paid,
    _BulkField.shipped => o.isShipped,
    _BulkField.received => o.receivedAt != null,
  };

  /// 대상이 모두 체크됐으면 true, 하나도 없으면 false, 일부면 null. 대상이 없으면 false.
  bool? stateOf(Iterable<TextbookOrder> orders) {
    final targets = orders.where(isTarget);
    if (targets.isEmpty) return false;
    final checked = targets.where(isChecked).length;
    if (checked == 0) return false;
    return checked == targets.length ? true : null;
  }
}

/// 전체 체크박스. 모두 체크된 상태에서 누르면 전체 해제, 그 외에는 전체 체크.
class _BulkCheckbox extends StatelessWidget {
  const _BulkCheckbox({
    required this.field,
    required this.orders,
    required this.enabled,
    required this.onBulk,
  });

  final _BulkField field;
  final List<TextbookOrder> orders;
  final bool enabled;
  final _OnBulk onBulk;

  @override
  Widget build(BuildContext context) {
    final state = field.stateOf(orders);
    final hasTargets = orders.any(field.isTarget);
    return Tooltip(
      message: '${field.label} 전체 ${state == true ? '해제' : '체크'}',
      child: Checkbox(
        tristate: true,
        value: state,
        onChanged: !enabled || !hasTargets
            ? null
            : (_) => onBulk(field, state != true),
      ),
    );
  }
}

/// 모바일용 전체 체크 줄 (표 머리행 대신).
class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.orders,
    required this.enabled,
    required this.onBulk,
  });

  final List<TextbookOrder> orders;
  final bool enabled;
  final _OnBulk onBulk;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text('전체', style: TextStyle(fontSize: 13, color: c.textSecondary)),
          for (final f in _BulkField.values)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BulkCheckbox(
                  field: f,
                  orders: orders,
                  enabled: enabled,
                  onBulk: onBulk,
                ),
                Text(f.label),
                const SizedBox(width: 8),
              ],
            ),
        ],
      ),
    );
  }
}

String _itemsText(TextbookOrder o) =>
    o.items.map((i) => '${i.title} ×${i.quantity}').join(', ');

class _OrdersList extends StatelessWidget {
  const _OrdersList({
    required this.orders,
    required this.busy,
    required this.onStatus,
    required this.onShipped,
    required this.onReceived,
    required this.onMove,
    required this.onBulk,
  });

  final List<TextbookOrder> orders;
  final Set<String> busy;
  final _OnStatus onStatus;
  final _OnToggle onShipped;
  final _OnToggle onReceived;
  final _OnMove onMove;
  final _OnBulk onBulk;

  @override
  Widget build(BuildContext context) {
    // 처리 중인 행이 있으면 전체 체크를 막는다.
    final bulkEnabled = busy.isEmpty;
    DataColumn bulkColumn(_BulkField f) => DataColumn(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(f.label),
          _BulkCheckbox(
            field: f,
            orders: orders,
            enabled: bulkEnabled,
            onBulk: onBulk,
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  // 체크 열까지 가로 스크롤 없이 보이도록 열을 좁게 둔다.
                  columnSpacing: 12,
                  horizontalMargin: 16,
                  columns: [
                    const DataColumn(label: Text('회원')),
                    const DataColumn(label: Text('교재')),
                    const DataColumn(label: Text('금액'), numeric: true),
                    const DataColumn(label: Text('상태')),
                    const DataColumn(label: Text('신청일')),
                    for (final f in _BulkField.values) bulkColumn(f),
                  ],
                  rows: [
                    for (final o in orders)
                      DataRow(
                        cells: [
                          DataCell(_MemberCell(o.member)),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                _itemsText(o),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(Text(formatWon(o.totalPrice))),
                          DataCell(
                            _StatusMenu(
                              order: o,
                              enabled: !busy.contains(o.id),
                              onStatus: onStatus,
                              onMove: onMove,
                            ),
                          ),
                          DataCell(Text(formatShortDateTime(o.createdAt))),
                          DataCell(
                            _PaidCheckbox(
                              order: o,
                              enabled: !busy.contains(o.id),
                              onStatus: onStatus,
                            ),
                          ),
                          DataCell(
                            _ShippedCheckbox(
                              order: o,
                              enabled: !busy.contains(o.id),
                              onShipped: onShipped,
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ReceivedCheckbox(
                                  order: o,
                                  enabled: !busy.contains(o.id),
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
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BulkBar(orders: orders, enabled: bulkEnabled, onBulk: onBulk),
            for (final o in orders) ...[
              _OrderCard(
                order: o,
                enabled: !busy.contains(o.id),
                onStatus: onStatus,
                onShipped: onShipped,
                onReceived: onReceived,
                onMove: onMove,
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
    required this.onStatus,
    required this.onShipped,
    required this.onReceived,
    required this.onMove,
  });

  final TextbookOrder order;
  final bool enabled;
  final _OnStatus onStatus;
  final _OnToggle onShipped;
  final _OnToggle onReceived;
  final _OnMove onMove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order.member?.name ?? '-'}  ${order.member?.studentId ?? ''}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _StatusMenu(
                  order: order,
                  enabled: enabled,
                  onStatus: onStatus,
                  onMove: onMove,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_itemsText(order)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order.round?.label ?? '-'} 회차',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                _MoveButton(order: order, enabled: enabled, onMove: onMove),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatWon(order.totalPrice)} · ${formatDateTime(order.createdAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const Text('입금확인'),
                _PaidCheckbox(
                  order: order,
                  enabled: enabled,
                  onStatus: onStatus,
                ),
              ],
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
    );
  }
}

class _PaidCheckbox extends StatelessWidget {
  const _PaidCheckbox({
    required this.order,
    required this.enabled,
    required this.onStatus,
  });

  final TextbookOrder order;
  final bool enabled;
  final _OnStatus onStatus;

  @override
  Widget build(BuildContext context) {
    final cancelled = order.status == OrderStatus.cancelled;
    return Checkbox(
      value: order.status == OrderStatus.paid,
      onChanged: !enabled || cancelled
          ? null
          : (v) => onStatus(
              order,
              v == true ? OrderStatus.paid : OrderStatus.requested,
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
    final box = Checkbox(
      value: order.isShipped,
      onChanged: !enabled || cancelled
          ? null
          : (v) => onShipped(order, v == true),
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
    return Checkbox(
      value: order.receivedAt != null,
      onChanged: !enabled || cancelled || !order.isShipped
          ? null
          : (v) => onReceived(order, v == true),
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

/// 상태 메뉴의 "다른 회차로 이동" 항목.
const _moveAction = #move;

/// 상태 변경 + 다른 회차로 이동 메뉴. (표에 열을 늘리지 않도록 한 메뉴에 둔다)
class _StatusMenu extends StatelessWidget {
  const _StatusMenu({
    required this.order,
    required this.enabled,
    required this.onStatus,
    required this.onMove,
  });

  final TextbookOrder order;
  final bool enabled;
  final _OnStatus onStatus;
  final _OnMove onMove;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      enabled: enabled,
      tooltip: '상태 변경 · 회차 이동',
      initialValue: order.status,
      onSelected: (v) => v is OrderStatus ? onStatus(order, v) : onMove(order),
      itemBuilder: (_) => [
        for (final s in OrderStatus.values)
          PopupMenuItem(value: s, child: Text(s.label)),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _moveAction,
          child: Row(
            children: [
              Icon(Icons.drive_file_move_outline, size: 20),
              SizedBox(width: 8),
              Text('다른 회차로 이동'),
            ],
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrderStatusChip(order.status),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    );
  }
}

/// 신청의 회차와 다른 회차로 옮기기 버튼.
class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.order,
    required this.enabled,
    required this.onMove,
  });

  final TextbookOrder order;
  final bool enabled;
  final _OnMove onMove;

  @override
  Widget build(BuildContext context) {
    final start = order.round?.start;
    return TextButton.icon(
      onPressed: enabled ? () => onMove(order) : null,
      icon: const Icon(Icons.drive_file_move_outline, size: 18),
      label: Text(start == null ? '이동' : '${start.month}/${start.day}'),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

/// 옮길 회차를 고른다. 신청 날짜와 상관없이 어느 회차로든 옮길 수 있다.
class _MoveRoundDialog extends StatelessWidget {
  const _MoveRoundDialog({required this.order, required this.rounds});

  final TextbookOrder order;

  /// 최신순. 첫 번째가 이번 회차.
  final List<OrderRound> rounds;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text('다른 회차로 이동'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '${order.member?.name ?? '회원'}님의 신청 '
                '(${formatShortDateTime(order.createdAt)})을 옮길 회차를 고르세요.',
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rounds.length,
                itemBuilder: (context, i) {
                  final r = rounds[i];
                  final mine = r.id == order.roundId;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(r.label),
                    subtitle: Text(
                      [
                        i == 0 ? '이번 회차' : '$i회차 전',
                        if (mine) '현재 회차',
                      ].join(' · '),
                    ),
                    trailing: mine ? const Icon(Icons.check) : null,
                    enabled: !mine,
                    onTap: () => Navigator.of(context).pop(r),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
      ],
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
