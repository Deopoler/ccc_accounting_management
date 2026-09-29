import 'package:intl/intl.dart';

final _wonFormat = NumberFormat.decimalPattern('ko_KR');

/// `1000` → `1,000원`
String formatWon(num amount) => '${_wonFormat.format(amount)}원';

/// 로컬(한국) 시간 기준 `2026.09.29`
String formatDate(DateTime date) =>
    DateFormat('yyyy.MM.dd').format(date.toLocal());

/// 로컬(한국) 시간 기준 `2026.09.29 14:05`
String formatDateTime(DateTime date) =>
    DateFormat('yyyy.MM.dd HH:mm').format(date.toLocal());
