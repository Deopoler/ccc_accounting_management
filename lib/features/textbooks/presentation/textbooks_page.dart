import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/order_round.dart';
import '../domain/textbook.dart';
import '../domain/textbook_order.dart';
import 'textbook_providers.dart';
import 'widgets/order_widgets.dart';

/// 교재 목록 및 신청. [editOrderId] 가 있으면 해당 신청을 수정한다.
class TextbooksPage extends ConsumerStatefulWidget {
  const TextbooksPage({super.key, this.editOrderId});

  final String? editOrderId;

  @override
  ConsumerState<TextbooksPage> createState() => _TextbooksPageState();
}

class _TextbooksPageState extends ConsumerState<TextbooksPage> {
  Map<String, int> _quantities = {};
  String? _prefilledFor;
  bool _submitting = false;

  bool get _editing => widget.editOrderId != null;

  void _setQuantity(String textbookId, int value) {
    setState(() => _quantities = {..._quantities, textbookId: value});
  }

  Future<void> _submit(List<Textbook> textbooks) async {
    final total = _total(textbooks);
    final ok = await showConfirmDialog(
      context,
      title: _editing ? '신청 수정' : '교재 신청',
      message:
          '선택한 교재 ${_count()}권, 총 ${formatWon(total)}을 '
          '${_editing ? '수정' : '신청'}하시겠습니까?',
      confirmLabel: _editing ? '수정하기' : '신청하기',
    );
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    final repo = ref.read(textbookRepositoryProvider);
    try {
      final String orderId;
      if (_editing) {
        orderId = widget.editOrderId!;
        await repo.updateOrder(orderId, _quantities);
        ref.invalidate(orderProvider(orderId));
      } else {
        orderId = await repo.placeOrder(_quantities);
      }
      ref.invalidate(myOrdersProvider);
      if (!mounted) return;
      setState(() => _quantities = {});
      context.go(
        Uri(
          path: AppRoutes.textbookOrderComplete(orderId),
          queryParameters: _editing ? {'edited': '1'} : null,
        ).toString(),
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  int _count() => _quantities.values.fold(0, (a, b) => a + b);

  int _total(List<Textbook> textbooks) {
    var total = 0;
    for (final t in textbooks) {
      total += (_quantities[t.id] ?? 0) * t.price;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final textbooks = ref.watch(textbooksProvider);
    final round = ref.watch(currentRoundProvider);
    final editOrder = _editing
        ? ref.watch(orderProvider(widget.editOrderId!))
        : const AsyncData<TextbookOrder?>(null);

    // 수정 모드: 기존 신청 수량으로 한 번만 채운다.
    final order = editOrder.value;
    if (_editing && order != null && _prefilledFor != order.id) {
      _prefilledFor = order.id;
      _quantities = {for (final i in order.items) i.textbookId: i.quantity};
    }

    final loading = [textbooks, round, editOrder];
    final error = loading.where((v) => v.hasError).firstOrNull;
    if (error != null) {
      return ErrorView(
        error: error.error!,
        onRetry: () {
          ref.invalidate(textbooksProvider);
          ref.invalidate(currentRoundProvider);
          if (_editing) ref.invalidate(orderProvider(widget.editOrderId!));
        },
      );
    }
    if (loading.any((v) => !v.hasValue)) return const LoadingView();

    final currentRound = round.requireValue;
    final books = textbooks.requireValue;

    if (_editing) {
      if (order == null) {
        return const EmptyView(message: '신청 내역을 찾을 수 없습니다.');
      }
      if (!order.canMemberEdit(currentRound.start)) {
        return EmptyView(
          icon: Icons.lock_outline,
          message: '입금확인되었거나 마감된 신청은 수정할 수 없습니다.',
          action: OutlinedButton(
            onPressed: () => context.go(AppRoutes.myOrders),
            child: const Text('내 신청 내역'),
          ),
        );
      }
    }

    // 수정 중인 신청에 포함된 비활성 교재도 목록에 보여야 수량을 줄일 수 있다.
    final visible = books
        .where((t) => t.isActive || (_quantities[t.id] ?? 0) > 0)
        .toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              PageBody(
                maxWidth: 800,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RoundBanner(
                      round: currentRound,
                      editing: _editing,
                      onCancelEdit: () => context.go(AppRoutes.myOrders),
                    ),
                    const SizedBox(height: 16),
                    if (visible.isEmpty)
                      const EmptyView(
                        icon: Icons.menu_book_outlined,
                        message: '현재 신청 가능한 교재가 없습니다.',
                      ),
                    for (final t in visible) ...[
                      _TextbookTile(
                        textbook: t,
                        quantity: _quantities[t.id] ?? 0,
                        onChanged: (v) => _setQuantity(t.id, v),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        _SubmitBar(
          count: _count(),
          total: _total(books),
          label: _editing ? '수정하기' : '신청하기',
          submitting: _submitting,
          onSubmit: _count() == 0 ? null : () => _submit(books),
        ),
      ],
    );
  }
}

class _RoundBanner extends StatelessWidget {
  const _RoundBanner({
    required this.round,
    required this.editing,
    required this.onCancelEdit,
  });

  final OrderRound round;
  final bool editing;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        child: Row(
          children: [
            Icon(
              editing ? Icons.edit_note : Icons.schedule,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    editing ? '신청 내역 수정 중' : '이번 회차 ${round.label}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${round.deadlineLabel}에 마감됩니다. 마감 전까지 수정·취소할 수 있습니다.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (editing)
              TextButton(onPressed: onCancelEdit, child: const Text('수정 취소')),
          ],
        ),
      ),
    );
  }
}

class _TextbookTile extends StatelessWidget {
  const _TextbookTile({
    required this.textbook,
    required this.quantity,
    required this.onChanged,
  });

  final Textbook textbook;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = quantity > 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: textbook.isActive
            ? () => onChanged(quantity == 0 ? 1 : 0)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(textbook.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          formatWon(textbook.price),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!textbook.isActive)
                          StatusBadge(
                            label: '신청 불가',
                            background:
                                theme.colorScheme.surfaceContainerHighest,
                            foreground: theme.colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              QuantityStepper(
                value: quantity,
                canIncrement: textbook.isActive,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.count,
    required this.total,
    required this.label,
    required this.submitting,
    required this.onSubmit,
  });

  final int count;
  final int total;
  final String label;
  final bool submitting;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: PageBody(
          maxWidth: 800,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('선택 $count권', style: theme.textTheme.bodySmall),
                    Text(
                      formatWon(total),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: submitting ? null : onSubmit,
                child: submitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
