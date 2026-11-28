import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/focus_ring.dart';

class AdminTabItem {
  const AdminTabItem({required this.id, required this.label});

  final String id;
  final String label;
}

/// 관리자 화면 내부의 하위 탭 막대.
class AdminTabBar extends StatelessWidget {
  const AdminTabBar({
    super.key,
    required this.tabs,
    required this.selectedId,
    required this.onSelected,
    this.maxWidth = 1200,
  });

  final List<AdminTabItem> tabs;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.divider)),
      ),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _AdminTabButton(
                    item: tabs[i],
                    selected: tabs[i].id == selectedId,
                    onTap: () => onSelected(tabs[i].id),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminTabButton extends StatelessWidget {
  const _AdminTabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AdminTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: FocusRing(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? c.primary : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              item.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? c.primary : c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
