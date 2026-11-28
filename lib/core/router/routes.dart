import 'package:material_ui/material_ui.dart';

abstract final class AppRoutes {
  static const login = '/login';
  static const changePassword = '/change-password';
  static const splash = '/loading';
  static const signup = '/signup';
  static const pending = '/pending';

  static const home = '/home';
  static const textbooks = '/textbooks';
  static String textbookOrderComplete(String orderId) =>
      '/textbooks/complete/$orderId';
  static String editTextbookOrder(String orderId) =>
      Uri(path: textbooks, queryParameters: {'edit': orderId}).toString();
  static const myOrders = '/my-orders';
  static const events = '/events';

  static const admin = '/admin';
  static const adminOrders = '/admin/orders';
  static String adminOrdersTab(String tab) =>
      Uri(path: adminOrders, queryParameters: {'tab': tab}).toString();
  static const adminEvents = '/admin/events';
  static String adminEventDetail(String eventId) => '/admin/events/$eventId';
  static const adminDeposits = '/admin/deposits';
  static const adminMembers = '/admin/members';
  static String adminMembersTab(String tab) =>
      Uri(path: adminMembers, queryParameters: {'tab': tab}).toString();
  static const adminCentral = '/admin/central';
  static String adminCentralTab(String tab) =>
      Uri(path: adminCentral, queryParameters: {'tab': tab}).toString();

  // Legacy paths preserved for redirects (bookmarks and push notifications).
  static const adminTextbooks = '/admin/textbooks';
  static const adminSettings = '/admin/settings';
  static const adminCampuses = '/admin/campuses';
  static const adminFeedback = '/admin/feedback';

  /// 총괄 관리자만 들어갈 수 있는 관리자 화면.
  static const centralOnly = [adminCentral, adminCampuses, adminFeedback];
}

class NavDestination {
  const NavDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.subtitle,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? subtitle;
}

const memberDestinations = <NavDestination>[
  NavDestination(
    path: AppRoutes.home,
    label: '홈',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  NavDestination(
    path: AppRoutes.textbooks,
    label: '교재 신청',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book,
  ),
  NavDestination(
    path: AppRoutes.myOrders,
    label: '내 신청',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
  ),
  NavDestination(
    path: AppRoutes.events,
    label: '이벤트',
    icon: Icons.event_outlined,
    selectedIcon: Icons.event,
  ),
];

const adminDestinations = <NavDestination>[
  NavDestination(
    path: AppRoutes.adminOrders,
    label: '교재',
    subtitle: '신청 현황 · 교재·카테고리 · 마감',
    icon: Icons.fact_check_outlined,
    selectedIcon: Icons.fact_check,
  ),
  NavDestination(
    path: AppRoutes.adminEvents,
    label: '이벤트',
    subtitle: '이벤트 등록 · 송금 확인 · 미납자',
    icon: Icons.event_note_outlined,
    selectedIcon: Icons.event_note,
  ),
  NavDestination(
    path: AppRoutes.adminDeposits,
    label: '입금 내역',
    subtitle: '자동 입금 확인 · 검토 필요',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
  ),
  NavDestination(
    path: AppRoutes.adminMembers,
    label: '회원·계좌',
    subtitle: '가입 승인 · 송금 계좌 · 알림',
    icon: Icons.group_outlined,
    selectedIcon: Icons.group,
  ),
];

/// 총괄 관리자에게만 보이는 메뉴.
const centralDestinations = <NavDestination>[
  NavDestination(
    path: AppRoutes.adminCentral,
    label: '총괄 관리',
    subtitle: '캠퍼스 · 피드백',
    icon: Icons.domain_outlined,
    selectedIcon: Icons.domain,
  ),
];

/// 화면 제목과 뒤로가기 대상(상위 경로).
typedef RouteMeta = ({String title, String? parent});

RouteMeta routeMetaFor(String path) {
  final uri = Uri.parse(path);
  final normalized = uri.path;
  final segments = uri.pathSegments;
  if (segments.length == 3 &&
      segments[0] == 'admin' &&
      segments[1] == 'events') {
    return (title: '이벤트 송금 현황', parent: AppRoutes.adminEvents);
  }
  if (segments.length == 3 &&
      segments[0] == 'textbooks' &&
      segments[1] == 'complete') {
    return (title: '신청 완료', parent: null);
  }
  if (normalized == AppRoutes.myOrders) return (title: '내 신청 내역', parent: null);
  for (final d in memberDestinations) {
    if (d.path == normalized) return (title: d.label, parent: null);
  }
  for (final d in [...adminDestinations, ...centralDestinations]) {
    if (d.path == normalized) return (title: d.label, parent: AppRoutes.admin);
  }
  if (normalized == AppRoutes.admin) return (title: '관리자 메뉴', parent: null);
  return (title: 'CCC 회계', parent: null);
}

/// [location] 과 가장 길게 일치하는 목적지의 인덱스. 없으면 null.
int? matchDestination(List<NavDestination> destinations, String location) {
  final path = Uri.parse(location).path;
  int? best;
  var bestLength = -1;
  for (var i = 0; i < destinations.length; i++) {
    final p = destinations[i].path;
    final matches = path == p || path.startsWith('$p/');
    if (matches && p.length > bestLength) {
      best = i;
      bestLength = p.length;
    }
  }
  return best;
}
