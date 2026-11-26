const _trailingWrappers = {
  0x20, // space
  0x22, // "
  0x27, // '
  0x29, // )
  0x5D, // ]
  0x7D, // }
  0x3E, // >
  0x2019, // ’
  0x201D, // ”
  0x3009, // 〉
  0x300B, // 》
  0x300D, // 」
  0x300F, // 』
};

String _stripTrailingPunctuation(String s) {
  final runes = s.runes.toList();
  var end = runes.length;
  while (end > 0 && _trailingWrappers.contains(runes[end - 1])) {
    end--;
  }
  return String.fromCharCodes(runes.sublist(0, end));
}

bool? _hasBatchim(String word) {
  final trimmed = _stripTrailingPunctuation(word);
  if (trimmed.isEmpty) return null;
  final rune = trimmed.runes.last;
  if (rune >= 0xAC00 && rune <= 0xD7A3) {
    return (rune - 0xAC00) % 28 != 0;
  }
  // 0(영), 1(일), 3(삼), 6(육), 7(칠), 8(팔)은 받침이 있고, 2(이), 4(사), 5(오), 9(구)는 없다.
  return switch (rune) {
    0x30 || 0x31 || 0x33 || 0x36 || 0x37 || 0x38 => true,
    0x32 || 0x34 || 0x35 || 0x39 => false,
    _ => null,
  };
}

String _pickJosa(String word, String consonant, String vowel, String fallback) {
  return switch (_hasBatchim(word)) {
    true => '$word$consonant',
    false => '$word$vowel',
    null => '$word$fallback',
  };
}

/// 목적격 조사(`을`/`를`)를 붙여 반환한다. 판별할 수 없으면 `을(를)`을 붙인다.
String withObject(String word) => _pickJosa(word, '을', '를', '을(를)');

/// 방향 조사(`으로`/`로`)를 붙여 반환한다. 받침이 없거나 ㄹ 받침이면 `로`.
String withRo(String word) {
  final trimmed = _stripTrailingPunctuation(word);
  if (trimmed.isEmpty) return '$word(으)로';
  final rune = trimmed.runes.last;
  if (rune >= 0xAC00 && rune <= 0xD7A3) {
    final jong = (rune - 0xAC00) % 28;
    return jong == 0 || jong == 8 ? '$word로' : '$word으로';
  }
  // 1(일), 7(칠), 8(팔)은 ㄹ 받침, 2, 4, 5, 9는 받침 없음.
  return switch (rune) {
    0x31 || 0x37 || 0x38 || 0x32 || 0x34 || 0x35 || 0x39 => '$word로',
    0x30 || 0x33 || 0x36 => '$word으로',
    _ => '$word(으)로',
  };
}

/// 접속 조사(`과`/`와`)를 붙여 반환한다. 판별할 수 없으면 `과(와)`를 붙인다.
String withAnd(String word) => _pickJosa(word, '과', '와', '과(와)');
