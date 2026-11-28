import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../campus/presentation/admin_campuses_page.dart';
import '../../feedback/presentation/admin_feedback_page.dart';
import 'admin_section_tabs.dart';

/// 총괄 관리: 캠퍼스 관리 + 피드백함.
class AdminCentralPage extends StatefulWidget {
  const AdminCentralPage({super.key, this.tab});

  final String? tab;

  static const campusesTab = 'campuses';
  static const feedbackTab = 'feedback';

  static String normalizeTab(String? raw) =>
      raw == feedbackTab ? feedbackTab : campusesTab;

  @override
  State<AdminCentralPage> createState() => _AdminCentralPageState();
}

class _AdminCentralPageState extends State<AdminCentralPage> {
  late String _tab = AdminCentralPage.normalizeTab(widget.tab);

  @override
  void didUpdateWidget(covariant AdminCentralPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      _tab = AdminCentralPage.normalizeTab(widget.tab);
    }
  }

  void _selectTab(String id) {
    if (_tab == id) return;
    setState(() => _tab = id);
    GoRouter.maybeOf(context)?.go(AppRoutes.adminCentralTab(id));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTabBar(
          maxWidth: 800,
          selectedId: _tab,
          onSelected: _selectTab,
          tabs: const [
            AdminTabItem(id: AdminCentralPage.campusesTab, label: '캠퍼스'),
            AdminTabItem(id: AdminCentralPage.feedbackTab, label: '피드백'),
          ],
        ),
        Expanded(
          child: _tab == AdminCentralPage.feedbackTab
              ? const AdminFeedbackPage()
              : const AdminCampusesPage(),
        ),
      ],
    );
  }
}
