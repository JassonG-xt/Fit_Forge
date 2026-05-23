class CoachSlotExtractor {
  const CoachSlotExtractor();

  int? targetMinutes(String text) {
    final match = RegExp(r'(\d+)\s*分钟').firstMatch(text);
    if (match != null) {
      final value = int.tryParse(match.group(1) ?? '');
      if (value != null && value >= 5 && value <= 180) return value;
    }
    if (text.contains('半小时')) return 30;
    return null;
  }

  List<int> weekdays(String text) {
    const dayMap = {
      '周一': 1,
      '周二': 2,
      '周三': 3,
      '周四': 4,
      '周五': 5,
      '周六': 6,
      '周日': 7,
      '周天': 7,
      '星期一': 1,
      '星期二': 2,
      '星期三': 3,
      '星期四': 4,
      '星期五': 5,
      '星期六': 6,
      '星期日': 7,
      '星期天': 7,
    };
    final selected = <int>{};
    for (final entry in dayMap.entries) {
      if (text.contains(entry.key)) selected.add(entry.value);
    }
    return selected.toList()..sort();
  }

  ({int from, int to})? moveSessionPair(String text) {
    const moveVerbs = ['挪到', '移到', '移动到', '改到', '调到', '换到'];
    var verbStart = -1;
    var verbEnd = -1;
    for (final verb in moveVerbs) {
      final idx = text.indexOf(verb);
      if (idx >= 0 && (verbStart < 0 || idx < verbStart)) {
        verbStart = idx;
        verbEnd = idx + verb.length;
      }
    }
    if (verbStart < 0) return null;

    final dayRegex = RegExp(r'周[一二三四五六日天]|星期[一二三四五六日天]');
    final matches = dayRegex.allMatches(text).toList();
    if (matches.length != 2) return null;

    final before = matches.where((m) => m.end <= verbStart).toList();
    final after = matches.where((m) => m.start >= verbEnd).toList();
    if (before.length != 1 || after.length != 1) return null;

    final dayMap = {
      for (final day in weekdaysFromTokens.entries) day.key: day.value,
    };
    final from = dayMap[before.first.group(0)!];
    final to = dayMap[after.first.group(0)!];
    if (from == null || to == null || from == to) return null;
    return (from: from, to: to);
  }

  static const weekdaysFromTokens = {
    '周一': 1,
    '周二': 2,
    '周三': 3,
    '周四': 4,
    '周五': 5,
    '周六': 6,
    '周日': 7,
    '周天': 7,
    '星期一': 1,
    '星期二': 2,
    '星期三': 3,
    '星期四': 4,
    '星期五': 5,
    '星期六': 6,
    '星期日': 7,
    '星期天': 7,
  };
}
