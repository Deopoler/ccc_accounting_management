final _whitespaceRegExp = RegExp(r'\s+');

const List<String> _chosung = [
  'ㄱ',
  'ㄲ',
  'ㄴ',
  'ㄷ',
  'ㄸ',
  'ㄹ',
  'ㅁ',
  'ㅂ',
  'ㅃ',
  'ㅅ',
  'ㅆ',
  'ㅇ',
  'ㅈ',
  'ㅉ',
  'ㅊ',
  'ㅋ',
  'ㅌ',
  'ㅍ',
  'ㅎ',
];

final Map<int, int> _chosungCodeToIndex = {
  for (var i = 0; i < _chosung.length; i++) _chosung[i].codeUnitAt(0): i,
};

/// Returns `true` if [text] matches [query], supporting Korean initial
/// consonant (초성) search as well as standard case-insensitive substring match.
bool matchesKoreanQuery(String text, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return true;

  final lowerText = text.toLowerCase();
  final lowerQuery = trimmed.toLowerCase();
  if (lowerText.contains(lowerQuery)) return true;

  var hasChosung = false;
  for (var i = 0; i < lowerQuery.length; i++) {
    if (_chosungCodeToIndex.containsKey(lowerQuery.codeUnitAt(i))) {
      hasChosung = true;
      break;
    }
  }
  if (!hasChosung) return false;

  final cleanText = lowerText.replaceAll(_whitespaceRegExp, '');
  final cleanQuery = lowerQuery.replaceAll(_whitespaceRegExp, '');
  if (cleanQuery.isEmpty) return true;
  if (cleanQuery.length > cleanText.length) return false;

  final limit = cleanText.length - cleanQuery.length;
  for (var start = 0; start <= limit; start++) {
    var matched = true;
    for (var i = 0; i < cleanQuery.length; i++) {
      if (!_charMatches(
        cleanText.codeUnitAt(start + i),
        cleanQuery.codeUnitAt(i),
      )) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}

bool _charMatches(int textCode, int queryCode) {
  final chosungIndex = _chosungCodeToIndex[queryCode];
  if (chosungIndex != null) {
    if (textCode == queryCode) return true;
    if (textCode >= 0xAC00 && textCode <= 0xD7A3) {
      return (textCode - 0xAC00) ~/ 588 == chosungIndex;
    }
    return false;
  }
  return textCode == queryCode;
}
