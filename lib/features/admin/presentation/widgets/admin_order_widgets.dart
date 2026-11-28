import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/focus_ring.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../textbooks/domain/order_filter.dart';
import '../../../textbooks/domain/textbook_order.dart';
import '../../../textbooks/presentation/widgets/order_widgets.dart';

typedef OnOrderStatus = void Function(TextbookOrder order, OrderStatus status);
typedef OnOrderBulk = void Function(OrderBulkField field, bool value);

/// 선택한 신청에 한 번에 체크할 수 있는 항목. 취소된 신청은 모두 대상이 아니다.
enum OrderBulkField {
  paid('입금확인'),
  shipped('배송'),
  received('수령');

  const OrderBulkField(this.label);

  final String label;

  bool isTarget(TextbookOrder o) =>
      o.status != OrderStatus.cancelled &&
      (this != OrderBulkField.received || o.isShipped);

  bool isChecked(TextbookOrder o) => switch (this) {
    OrderBulkField.paid => o.status == OrderStatus.paid,
    OrderBulkField.shipped => o.isShipped,
    OrderBulkField.received => o.receivedAt != null,
  };
}

/// 상태 필터와 상태별 건수·금액 요약을 합친 타일 묶음.
/// 전체 상태는 취소를 제외한 합계를 표시한다.
class OrderStatusSummaryChips extends StatelessWidget {
  const OrderStatusSummaryChips({
    super.key,
    required this.status,
    required this.summary,
    required this.loading,
    required this.onChanged,
  });

  final OrderStatus? status;
  final Map<OrderStatus, StatusSummary>? summary;
  final bool loading;
  final ValueChanged<OrderStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final totalSummary = s == null
        ? null
        : (
            count:
                s[OrderStatus.requested]!.count + s[OrderStatus.paid]!.count,
            amount:
                s[OrderStatus.requested]!.amount + s[OrderStatus.paid]!.amount,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final tiles = [
          _StatusSummaryTile(
            label: '전체 상태',
            caption: '취소 제외',
            selected: status == null,
            loading: loading,
            summary: totalSummary,
            onTap: () => onChanged(null),
          ),
          for (final item in OrderStatus.values)
            _StatusSummaryTile(
              label: item.label,
              selected: status == item,
              loading: loading,
              summary: s?[item],
              onTap: () => onChanged(item),
            ),
        ];

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: 8),
                  Expanded(child: tiles[1]),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: tiles[2]),
                  const SizedBox(width: 8),
                  Expanded(child: tiles[3]),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: tiles[i]),
            ],
          ],
        );
      },
    );
  }
}

class _StatusSummaryTile extends StatelessWidget {
  const _StatusSummaryTile({
    required this.label,
    this.caption,
    required this.selected,
    required this.loading,
    required this.summary,
    required this.onTap,
  });

  final String label;
  final String? caption;
  final bool selected;
  final bool loading;
  final StatusSummary? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.sm);

    return Semantics(
      button: true,
      selected: selected,
      child: FocusRing(
        borderRadius: radius,
        child: Material(
          color: selected ? c.primarySoft : c.surfaceMuted,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: selected
                ? BorderSide(color: c.primary, width: 1.5)
                : BorderSide(color: c.surfaceStrong),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: selected ? c.primary : c.textPrimary,
                            ),
                          ),
                          if (caption != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              caption!,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(height: 4),
                      const SkeletonRegion(
                        child: Row(
                          children: [
                            SkeletonText(
                              width: 32,
                              fontSize: 15,
                              lineHeight: 1.35,
                              announce: false,
                            ),
                            SizedBox(width: 6),
                            Expanded(
                              child: SkeletonText(
                                maxWidth: 72,
                                fontSize: 13,
                                lineHeight: 1.35,
                                announce: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (summary != null) ...[
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${summary!.count}건',
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              formatWon(summary!.amount),
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 교재별 집계 아코디언. 기본 접힘 상태이며 취소된 신청은 제외한다.
class TextbookTallyAccordion extends StatefulWidget {
  const TextbookTallyAccordion({
    super.key,
    required List<TextbookOrder> this.orders,
    required this.textbookId,
  }) : loading = false;

  const TextbookTallyAccordion.loading({super.key})
    : orders = null,
      textbookId = null,
      loading = true;

  final List<TextbookOrder>? orders;
  final String? textbookId;
  final bool loading;

  @override
  State<TextbookTallyAccordion> createState() => _TextbookTallyAccordionState();
}

class _TextbookTallyAccordionState extends State<TextbookTallyAccordion> {
  bool _expanded = false;

  void _toggle() {
    if (widget.loading) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppRadius.lg);

    final tallies = widget.loading
        ? const <TextbookTally>[]
        : (tallyByTextbook(widget.orders!).entries
              .where(
                (e) => widget.textbookId == null || e.key == widget.textbookId,
              )
              .map((e) => e.value)
              .toList()
            ..sort((a, b) => a.title.compareTo(b.title)));
    final totalQty = tallies.fold(0, (s, t) => s + t.quantity);
    final totalAmount = tallies.fold(0, (s, t) => s + t.amount);
    final isExpanded = !widget.loading && _expanded;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: isExpanded,
            enabled: !widget.loading,
            child: FocusRing(
              borderRadius: radius,
              child: InkWell(
                borderRadius: radius,
                onTap: widget.loading ? null : _toggle,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              Text(
                                '교재별 집계 (취소 제외)',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (widget.loading)
                                const SkeletonRegion(
                                  child: SkeletonBox(
                                    width: 112,
                                    height: 16,
                                    announce: false,
                                  ),
                                )
                              else
                                Text(
                                  '총 $totalQty권 · ${formatWon(totalAmount)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: widget.loading
                              ? c.textDisabled
                              : c.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: tallies.isEmpty
                  ? Text('집계할 신청이 없습니다.', style: theme.textTheme.bodyMedium)
                  : Table(
                      columnWidths: const {
                        0: FlexColumnWidth(),
                        1: IntrinsicColumnWidth(),
                        2: IntrinsicColumnWidth(),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
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
            ),
          ],
        ],
      ),
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
        ? Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)
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
              border: Border(
                bottom: BorderSide(color: context.colors.surfaceStrong),
              ),
            )
          : null,
      children: [cell(a), cell(b, right: true), cell(c, right: true)],
    );
  }
}

/// 단일 상태 변경 메뉴. 취소 항목은 구분선 아래에 분리한다.
class OrderStatusMenu extends StatelessWidget {
  const OrderStatusMenu({
    super.key,
    required this.order,
    required this.enabled,
    required this.onStatus,
  });

  final TextbookOrder order;
  final bool enabled;
  final OnOrderStatus onStatus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<OrderStatus>(
      enabled: enabled,
      tooltip: '상태 변경',
      initialValue: order.status,
      onSelected: (s) => onStatus(order, s),
      itemBuilder: (context) => [
        PopupMenuItem<OrderStatus>(
          value: OrderStatus.requested,
          child: Text(OrderStatus.requested.label),
        ),
        PopupMenuItem<OrderStatus>(
          value: OrderStatus.paid,
          child: Text(OrderStatus.paid.label),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<OrderStatus>(
          value: OrderStatus.cancelled,
          child: Text(
            OrderStatus.cancelled.label,
            style: TextStyle(color: context.colors.error),
          ),
        ),
      ],
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OrderStatusChip(order.status),
              Icon(
                Icons.arrow_drop_down,
                size: 20,
                color: enabled ? c.textSecondary : c.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 선택 막대. 1건 이상 선택했을 때만 일괄 처리 버튼을 렌더링한다.
class OrderBulkActionBar extends StatelessWidget {
  const OrderBulkActionBar({
    super.key,
    required this.orders,
    required this.picked,
    required this.enabled,
    required this.showPickAll,
    required this.onPickAll,
    required this.onBulk,
    required this.onShift,
  });

  final List<TextbookOrder> orders;
  final Set<String> picked;
  final bool enabled;

  /// 표에는 머리행에 전체 선택이 있으므로 카드 목록에서만 보인다.
  final bool showPickAll;
  final ValueChanged<bool> onPickAll;
  final OnOrderBulk onBulk;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = orders.where((o) => picked.contains(o.id)).length;
    final all = orders.isNotEmpty && count == orders.length;

    if (count == 0) {
      if (!showPickAll) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            MergeSemantics(
              child: Semantics(
                label: '전체 선택',
                child: Checkbox(
                  value: false,
                  onChanged: enabled && orders.isNotEmpty
                      ? (_) => onPickAll(true)
                      : null,
                ),
              ),
            ),
            Text(
              '전체 선택',
              style: TextStyle(
                fontSize: 14,
                color: enabled ? c.textSecondary : c.textDisabled,
              ),
            ),
          ],
        ),
      );
    }

    final active = enabled;
    final compactStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
    Widget label(Widget child) =>
        showPickAll ? FittedBox(fit: BoxFit.scaleDown, child: child) : child;

    final header = Row(
      mainAxisSize: showPickAll ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (showPickAll)
          MergeSemantics(
            child: Semantics(
              label: '전체 선택',
              child: Checkbox(
                tristate: true,
                value: all ? true : null,
                onChanged: enabled ? (_) => onPickAll(!all) : null,
              ),
            ),
          ),
        Flexible(
          child: Text(
            '$count건 선택',
            style: TextStyle(
              fontSize: 14,
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    final clear = TextButton(
      onPressed: enabled ? () => onPickAll(false) : null,
      child: const Text('선택 해제'),
    );
    final fieldButtons = [
      for (final f in OrderBulkField.values)
        MenuAnchor(
          builder: (context, controller, _) => OutlinedButton(
            style: showPickAll ? compactStyle : null,
            onPressed: !active
                ? null
                : () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
            child: label(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(f.label),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.check_box_outlined),
              onPressed: () => onBulk(f, true),
              child: Text('${f.label} 체크'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.check_box_outline_blank),
              onPressed: () => onBulk(f, false),
              child: Text('${f.label} 해제'),
            ),
          ],
        ),
    ];
    Widget shiftButton(int offset) => OutlinedButton.icon(
      style: showPickAll ? compactStyle : null,
      onPressed: active ? () => onShift(offset) : null,
      icon: Icon(
        offset < 0 ? Icons.chevron_left : Icons.chevron_right,
        size: 18,
      ),
      label: label(Text(offset < 0 ? '이전 회차로' : '다음 회차로')),
    );

    if (showPickAll) {
      Widget evenRow(List<Widget> children) => Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: children[i]),
          ],
        ],
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: header),
                clear,
              ],
            ),
            const SizedBox(height: 4),
            evenRow(fieldButtons),
            const SizedBox(height: 8),
            evenRow([shiftButton(-1), shiftButton(1)]),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          header,
          ...fieldButtons,
          shiftButton(-1),
          shiftButton(1),
          clear,
        ],
      ),
    );
  }
}
