import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/korean_search.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/order_round.dart';
import '../domain/textbook.dart';
import '../domain/textbook_category.dart';
import '../domain/textbook_order.dart';
import 'textbook_providers.dart';
import 'widgets/order_widgets.dart';
import '../../campus/presentation/campus_providers.dart';
import '../../deposits/presentation/deposit_providers.dart';
import '../../push/presentation/push_providers.dart';

/// 교재 신청: 카테고리 선택 → 교재 선택. [editOrderId] 가 있으면 해당 신청을 수정한다.
///
/// [categoryId] 는 URL 쿼리(`?category=`)로 들어오며, 바뀌어도 이 위젯의 상태(선택 수량)는
/// 유지된다. 여러 카테고리에서 고른 교재를 한 번에 신청한다.
class TextbooksPage extends ConsumerStatefulWidget {
  const TextbooksPage({super.key, this.editOrderId, this.categoryId});

  final String? editOrderId;
  final String? categoryId;

  @override
  ConsumerState<TextbooksPage> createState() => _TextbooksPageState();
}

class _TextbooksPageState extends ConsumerState<TextbooksPage> {
  Map<String, int> _editQuantities = {};
  String? _prefilledFor;
  bool _editDirty = false;
  bool _wasActive = true;
  bool _submitting = false;
  final _search = TextEditingController();

  bool get _editing => widget.editOrderId != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (_editing && _wasActive && !active) {
      _editQuantities = {};
      _prefilledFor = null;
      _editDirty = false;
    }
    _wasActive = active;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _cancelEdit() {
    setState(() {
      _editQuantities = {};
      _prefilledFor = null;
      _editDirty = false;
    });
    context.go(AppRoutes.myOrders);
  }

  /// 카테고리 이동. 수정 모드면 edit 쿼리를 유지한다.
  void _openCategory(String? categoryId) {
    context.go(
      Uri(
        path: AppRoutes.textbooks,
        queryParameters: {'edit': ?widget.editOrderId, 'category': ?categoryId},
      ).toString(),
    );
  }

  void _setQuantity(String textbookId, int value) {
    if (_editing) {
      setState(() {
        _editDirty = true;
        _editQuantities = {..._editQuantities, textbookId: value};
      });
    } else {
      ref.read(textbookCartProvider.notifier).setQuantity(textbookId, value);
    }
  }

  Future<void> _submit(
    List<Textbook> textbooks,
    Map<String, int> quantities,
  ) async {
    final total = _total(textbooks, quantities);
    final ok = await showConfirmDialog(
      context,
      title: _editing ? '신청 수정' : '교재 신청',
      message:
          '선택한 교재 ${_count(quantities)}권, 총 ${formatWon(total)}을 '
          '${_editing ? '수정' : '신청'}하시겠습니까?',
      confirmLabel: _editing ? '수정하기' : '신청하기',
      onConfirm: _editing
          ? null
          : () {
              // Safari / iOS 는 사용자 탭 제스처 안에서만 알림 권한을 물을 수 있으므로
              // 확인 버튼을 누른 직후(네트워크 await 전) 동기적으로 시작하고, 신청은 이를 기다리지 않는다.
              ref.read(signupPushProvider.notifier).enableOnOrderInGesture();
            },
    );
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    final repo = ref.read(textbookRepositoryProvider);
    try {
      final String orderId;
      if (_editing) {
        orderId = widget.editOrderId!;
        await repo.updateOrder(orderId, quantities);
        ref.invalidate(orderProvider(orderId));
      } else {
        orderId = await repo.placeOrder(quantities);
        ref.read(textbookCartProvider.notifier).clear();
      }
      ref.invalidate(myOrdersProvider);
      ref.invalidate(unpaidLinkTargetsProvider);
      if (!mounted) return;
      if (_editing) {
        setState(() {
          _editQuantities = {};
          _prefilledFor = null;
          _editDirty = false;
        });
      }
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

  List<Widget> _tiles(List<Textbook> textbooks, Map<String, int> quantities) =>
      [
        for (final t in textbooks) ...[
          _TextbookTile(
            textbook: t,
            quantity: quantities[t.id] ?? 0,
            onChanged: (v) => _setQuantity(t.id, v),
          ),
          const SizedBox(height: 8),
        ],
      ];

  int _count(Map<String, int> quantities) =>
      quantities.values.fold(0, (a, b) => a + b);

  int _total(List<Textbook> textbooks, Map<String, int> quantities) {
    var total = 0;
    for (final t in textbooks) {
      total += (quantities[t.id] ?? 0) * t.price;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Textbook>>>(
      textbooksProvider(CampusScope.member),
      (_, next) {
        if (_editing || !next.hasUsableValue || next.isLoading) return;
        final activeIds = {
          for (final b in next.requireValue)
            if (b.isActive) b.id,
        };
        ref.read(textbookCartProvider.notifier).prune(activeIds);
      },
    );

    final textbooks = ref.watch(textbooksProvider(CampusScope.member));
    final categories = ref.watch(
      textbookCategoriesProvider(CampusScope.member),
    );
    final round = ref.watch(currentRoundProvider);
    final editOrder = _editing
        ? ref.watch(orderProvider(widget.editOrderId!))
        : const AsyncData<TextbookOrder?>(null);

    // 수정 모드: 편집 전까지는 서버 신청 수량으로 채운다.
    final order = editOrder.hasUsableValue ? editOrder.requireValue : null;
    if (_editing && order != null && (!_editDirty || _prefilledFor != order.id)) {
      _prefilledFor = order.id;
      _editQuantities = {for (final i in order.items) i.textbookId: i.quantity};
    }
    final rawCart = _editing ? const <String, int>{} : ref.watch(textbookCartProvider);

    final loading = [textbooks, categories, round, editOrder];
    if (loading.any((v) => v.isLoading && !v.hasUsableValue)) {
      return const LoadingView();
    }
    final error = loading.where((v) => v.hasError).firstOrNull;
    if (error != null) {
      return ErrorView(
        error: error.error!,
        onRetry: () {
          ref.invalidate(textbooksProvider);
          ref.invalidate(textbookCategoriesProvider);
          ref.invalidate(currentRoundProvider);
          if (_editing) ref.invalidate(orderProvider(widget.editOrderId!));
        },
      );
    }
    if (loading.any((v) => !v.hasUsableValue) || round.requireValue == null) {
      return const LoadingView();
    }

    final refreshing = loading.any((v) => v.isBackgroundRefreshing);
    final currentRound = round.requireValue!;
    final books = textbooks.requireValue;

    final Map<String, int> quantities;
    if (_editing) {
      quantities = _editQuantities;
    } else {
      final activeIds = {
        for (final b in books)
          if (b.isActive) b.id,
      };
      quantities = {
        for (final e in rawCart.entries)
          if (activeIds.contains(e.key) && e.value > 0) e.key: e.value,
      };
      if (quantities.length != rawCart.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(textbookCartProvider.notifier).prune(activeIds);
          }
        });
      }
    }

    if (_editing) {
      if (order == null) {
        return RefreshOverlay(
          refreshing: refreshing,
          child: const EmptyView(message: '신청 내역을 찾을 수 없습니다.'),
        );
      }
      if (!order.canMemberEdit(currentRound)) {
        return RefreshOverlay(
          refreshing: refreshing,
          child: EmptyView(
            icon: Icons.lock_outline,
            message: '입금확인되었거나 마감된 신청은 수정할 수 없습니다.',
            action: OutlinedButton(
              onPressed: () => context.go(AppRoutes.myOrders),
              child: const Text('내 신청 내역'),
            ),
          ),
        );
      }
    }

    // 수정 중인 신청에 포함된 비활성 교재도 목록에 보여야 수량을 줄일 수 있다.
    final visible = books
        .where((t) => t.isActive || (_editing && (quantities[t.id] ?? 0) > 0))
        .toList();
    final groups = groupByCategory(categories.requireValue, visible);

    final query = _search.text.trim().toLowerCase();
    final List<Widget> content;
    if (widget.categoryId != null) {
      final group = groups.where((g) => g.id == widget.categoryId).firstOrNull;
      content = [
        _CategoryHeader(
          name: group?.name ?? '카테고리',
          onBack: () => _openCategory(null),
        ),
        const SizedBox(height: 12),
        if (group == null)
          const EmptyView(message: '이 카테고리에는 신청 가능한 교재가 없습니다.')
        else
          ..._tiles(group.textbooks, quantities),
      ];
    } else if (query.isNotEmpty) {
      final hits = visible
          .where((t) => matchesKoreanQuery(t.title, query))
          .toList();
      content = [
        _SearchField(controller: _search, onChanged: () => setState(() {})),
        const SizedBox(height: 12),
        if (hits.isEmpty)
          const EmptyView(message: '검색 결과가 없습니다.')
        else
          ..._tiles(hits, quantities),
      ];
    } else {
      content = [
        _SearchField(controller: _search, onChanged: () => setState(() {})),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          const EmptyView(
            icon: Icons.menu_book_outlined,
            message: '현재 신청 가능한 교재가 없습니다.',
          ),
        for (final g in groups) ...[
          _CategoryTile(
            group: g,
            selected: g.textbooks.fold(
              0,
              (s, t) => s + (quantities[t.id] ?? 0),
            ),
            onTap: () => _openCategory(g.id),
          ),
          const SizedBox(height: 8),
        ],
      ];
    }

    final selectedCount = _count(quantities);
    return RefreshOverlay(
      refreshing: refreshing,
      child: Column(
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
                        onCancelEdit: _cancelEdit,
                      ),
                      const SizedBox(height: 16),
                      ...content,
                    ],
                  ),
                ),
              ],
            ),
          ),
          _SubmitBar(
            count: selectedCount,
            total: _total(books, quantities),
            label: _editing ? '수정하기' : '신청하기',
            submitting: _submitting,
            onSubmit: selectedCount == 0
                ? null
                : () => _submit(books, quantities),
          ),
        ],
      ),
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
    final c = context.colors;
    return Card(
      color: c.primarySoft,
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
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${round.deadlineLabel}에 마감됩니다. 마감 전까지 수정·취소할 수 있습니다.',
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
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
        side: selected
            ? BorderSide(color: context.colors.primary, width: 1.5)
            : BorderSide.none,
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
                        AmountText(textbook.price, size: AmountSize.small),
                        if (!textbook.isActive)
                          const AppBadge('신청 불가', tone: BadgeTone.muted),
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
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      child: SafeArea(
        top: false,
        child: PageBody(
          maxWidth: 800,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '선택 $count권',
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                    AmountText(total),
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

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: '교재명으로 찾기',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '지우기',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final CategoryGroup group;

  /// 이 카테고리에서 고른 권수
  final int selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
        leading: Icon(
          Icons.folder_outlined,
          color: context.colors.textSecondary,
        ),
        title: Text(group.name, style: theme.textTheme.titleMedium),
        subtitle: Text('교재 ${group.textbooks.length}종'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected > 0) AppBadge('$selected권 선택', tone: BadgeTone.accent),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.name, required this.onBack});

  final String name;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '카테고리 목록',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            name,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(onPressed: onBack, child: const Text('다른 카테고리')),
      ],
    );
  }
}
