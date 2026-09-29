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
  static const adminMembers = '/admin/members';
  static const adminTextbooks = '/admin/textbooks';
  static const adminOrders = '/admin/orders';
  static const adminEvents = '/admin/events';
  static String adminEventDetail(String eventId) => '/admin/events/$eventId';
  static const adminSettings = '/admin/settings';
}

class NavDestination {
  const NavDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
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
    path: AppRoutes.adminMembers,
    label: '회원 관리',
    icon: Icons.group_outlined,
    selectedIcon: Icons.group,
  ),
  NavDestination(
    path: AppRoutes.adminTextbooks,
    label: '교재 관리',
    icon: Icons.library_books_outlined,
    selectedIcon: Icons.library_books,
  ),
  NavDestination(
    path: AppRoutes.adminOrders,
    label: '교재 신청 현황',
    icon: Icons.fact_check_outlined,
    selectedIcon: Icons.fact_check,
  ),
  NavDestination(
    path: AppRoutes.adminEvents,
    label: '이벤트 관리',
    icon: Icons.event_note_outlined,
    selectedIcon: Icons.event_note,
  ),
  NavDestination(
    path: AppRoutes.adminSettings,
    label: '설정',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
];

/// 화면 제목과 뒤로가기 대상(상위 경로).
typedef RouteMeta = ({String title, String? parent});

RouteMeta routeMetaFor(String path) {
  final segments = Uri.parse(path).pathSegments;
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
  if (path == AppRoutes.myOrders) return (title: '내 신청 내역', parent: null);
  for (final d in memberDestinations) {
    if (d.path == path) return (title: d.label, parent: null);
  }
  for (final d in adminDestinations) {
    if (d.path == path) return (title: d.label, parent: AppRoutes.admin);
  }
  if (path == AppRoutes.admin) return (title: '관리자 메뉴', parent: null);
  return (title: 'CCC 회계', parent: null);
}

/// [location] 과 가장 길게 일치하는 목적지의 인덱스. 없으면 null.
int? matchDestination(List<NavDestination> destinations, String location) {
  int? best;
  var bestLength = -1;
  for (var i = 0; i < destinations.length; i++) {
    final p = destinations[i].path;
    final matches = location == p || location.startsWith('$p/');
    if (matches && p.length > bestLength) {
      best = i;
      bestLength = p.length;
    }
  }
  return best;
}
