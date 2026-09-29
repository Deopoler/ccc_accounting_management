import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/download/download.dart';
import '../../../core/utils/formatters.dart';
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

/// 회차 선택: 0 = 이번 회차, n = n회차 전, [_allRounds] = 전체.
const _allRounds = -1;
const _pastRoundOptions = 11;

class AdminOrdersPage extends ConsumerStatefulWidget {
  const AdminOrdersPage({super.key});

  @override
  ConsumerState<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends ConsumerState<AdminOrdersPage> {
  int _roundOffset = 0;
  String? _textbookId;
  OrderStatus? _status;
  final _search = TextEditingController();
  final Set<String> _busy = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime? _roundStart(OrderRound current) =>
      _roundOffset == _allRounds ? null : current.previousStart(_roundOffset);

  Future<void> _setStatus(
    DateTime? round,
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

  void _export(
    List<TextbookOrder> orders,
    DateTime? roundStart, {
    required bool tally,
  }) {
    final round = roundStart == null ? '전체회차' : toDateOnly(roundStart);
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
    final round = ref.watch(currentRoundProvider);
    final textbooks = ref.watch(textbooksProvider);

    if (round.hasError) {
      return ErrorView(
        error: round.error!,
        onRetry: () => ref.invalidate(currentRoundProvider),
      );
    }
    if (!round.hasValue) return const LoadingView();

    final current = round.requireValue;
    final roundStart = _roundStart(current);
    final orders = ref.watch(adminOrdersProvider(roundStart));
    final books = textbooks.value ?? const <Textbook>[];

    return ListView(
      children: [
        PageBody(
          maxWidth: 1200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Filters(
                current: current,
                roundOffset: _roundOffset,
                onRoundChanged: (v) => setState(() => _roundOffset = v),
                textbooks: books,
                textbookId: _textbookId,
                onTextbookChanged: (v) => setState(() => _textbookId = v),
                status: _status,
                onStatusChanged: (v) => setState(() => _status = v),
                search: _search,
                onSearchChanged: () => setState(() {}),
              ),
              const SizedBox(height: 16),
              AsyncValueView(
                value: orders,
                onRetry: () => ref.invalidate(adminOrdersProvider(roundStart)),
                data: (all) {
                  final filtered = OrderFilter(
                    textbookId: _textbookId,
                    status: _status,
                    query: _search.text,
                  ).apply(all);
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
                              _export(filtered, roundStart, tally: tally),
                        ),
                      ),
                      if (filtered.isEmpty)
                        const EmptyView(message: '조건에 맞는 신청이 없습니다.')
                      else
                        _OrdersList(
                          orders: filtered,
                          busy: _busy,
                          onStatus: (o, s) => _setStatus(roundStart, o, s),
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
    required this.current,
    required this.roundOffset,
    required this.onRoundChanged,
    required this.textbooks,
    required this.textbookId,
    required this.onTextbookChanged,
    required this.status,
    required this.onStatusChanged,
    required this.search,
    required this.onSearchChanged,
  });

  final OrderRound current;
  final int roundOffset;
  final ValueChanged<int> onRoundChanged;
  final List<Textbook> textbooks;
  final String? textbookId;
  final ValueChanged<String?> onTextbookChanged;
  final OrderStatus? status;
  final ValueChanged<OrderStatus?> onStatusChanged;
  final TextEditingController search;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                DropdownMenu<int>(
                  width: 260,
                  label: const Text('회차'),
                  initialSelection: roundOffset,
                  onSelected: (v) => onRoundChanged(v ?? 0),
                  dropdownMenuEntries: [
                    DropdownMenuEntry(
                      value: 0,
                      label: '이번 회차 (${current.label})',
                    ),
                    for (var i = 1; i <= _pastRoundOptions; i++)
                      DropdownMenuEntry(
                        value: i,
                        label: roundLabel(current.previousStart(i)),
                      ),
                    const DropdownMenuEntry(value: _allRounds, label: '전체 회차'),
                  ],
                ),
                DropdownMenu<String?>(
                  width: 240,
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
                  width: 240,
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
          ],
        ),
      ),
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
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final s in OrderStatus.values)
              _StatCard(
                label: s.label,
                value: '${byStatus[s]!.count}건',
                sub: formatWon(byStatus[s]!.amount),
              ),
          ],
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
      decoration: header
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
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
  });

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(sub, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 목록 (데스크톱: 표 / 모바일: 카드)
// ----------------------------------------------------------------------------

typedef _OnStatus = void Function(TextbookOrder order, OrderStatus status);

String _itemsText(TextbookOrder o) =>
    o.items.map((i) => '${i.title} ×${i.quantity}').join(', ');

class _OrdersList extends StatelessWidget {
  const _OrdersList({
    required this.orders,
    required this.busy,
    required this.onStatus,
  });

  final List<TextbookOrder> orders;
  final Set<String> busy;
  final _OnStatus onStatus;

  @override
  Widget build(BuildContext context) {
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
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text('학번')),
                    DataColumn(label: Text('이름')),
                    DataColumn(label: Text('교재')),
                    DataColumn(label: Text('금액'), numeric: true),
                    DataColumn(label: Text('상태')),
                    DataColumn(label: Text('신청일')),
                    DataColumn(label: Text('입금확인')),
                  ],
                  rows: [
                    for (final o in orders)
                      DataRow(
                        cells: [
                          DataCell(Text(o.member?.studentId ?? '-')),
                          DataCell(Text(o.member?.name ?? '-')),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
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
                            ),
                          ),
                          DataCell(Text(formatDateTime(o.createdAt))),
                          DataCell(
                            _PaidCheckbox(
                              order: o,
                              enabled: !busy.contains(o.id),
                              onStatus: onStatus,
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
            for (final o in orders) ...[
              _OrderCard(
                order: o,
                enabled: !busy.contains(o.id),
                onStatus: onStatus,
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.enabled,
    required this.onStatus,
  });

  final TextbookOrder order;
  final bool enabled;
  final _OnStatus onStatus;

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
                _StatusMenu(order: order, enabled: enabled, onStatus: onStatus),
              ],
            ),
            const SizedBox(height: 4),
            Text(_itemsText(order)),
            const SizedBox(height: 4),
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

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({
    required this.order,
    required this.enabled,
    required this.onStatus,
  });

  final TextbookOrder order;
  final bool enabled;
  final _OnStatus onStatus;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<OrderStatus>(
      enabled: enabled,
      tooltip: '상태 변경',
      initialValue: order.status,
      onSelected: (s) => onStatus(order, s),
      itemBuilder: (_) => [
        for (final s in OrderStatus.values)
          PopupMenuItem(value: s, child: Text(s.label)),
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
