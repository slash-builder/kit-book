import 'game.dart';

class ScoreEntry {
  const ScoreEntry(this.seconds, this.when);
  final int seconds;
  final DateTime when;
}

/// Best times per difficulty, fastest first, ten at most.
class HighScores {
  HighScores([Map<Difficulty, List<ScoreEntry>>? initial]) : _by = initial ?? {};

  static const keep = 10;
  final Map<Difficulty, List<ScoreEntry>> _by;

  List<ScoreEntry> of(Difficulty d) => List.unmodifiable(_by[d] ?? const []);
  ScoreEntry? best(Difficulty d) => of(d).firstOrNull;

  /// Records a win and returns its rank (1 is the best), or null when it did not make the list.
  int? add(Difficulty d, int seconds, DateTime when) {
    final list = _by.putIfAbsent(d, () => []);
    // A tie ranks below the older score.
    var i = list.indexWhere((e) => e.seconds > seconds);
    if (i < 0) i = list.length;
    if (i >= keep) return null;
    list.insert(i, ScoreEntry(seconds, when));
    if (list.length > keep) list.removeLast();
    return i + 1;
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        for (final e in _by.entries)
          e.key.name: [
            for (final s in e.value) {'s': s.seconds, 'at': s.when.toUtc().toIso8601String()},
          ],
      };

  static HighScores fromJson(Object? json) {
    if (json is! Map) throw const FormatException('scores are not an object');
    final by = <Difficulty, List<ScoreEntry>>{};
    for (final d in Difficulty.values) {
      final list = json[d.name];
      if (list == null) continue;
      if (list is! List) throw FormatException('${d.name} scores are not a list');
      by[d] = [
        for (final e in list)
          if (e is Map && e['s'] is int && e['at'] is String)
            ScoreEntry(e['s'] as int, DateTime.parse(e['at'] as String))
          else
            throw FormatException('bad score in ${d.name}'),
      ]..sort((a, b) => a.seconds.compareTo(b.seconds));
    }
    return HighScores(by);
  }
}
