/// A version vector: one counter per replica (device). It is what lets two copies tell "you are behind" from "we both edited".
/// A timestamp cannot: it always orders two edits, so one of them is silently lost.
library;

enum VvOrder { equal, before, after, concurrent }

class Vv {
  const Vv(this.counts);
  static const empty = Vv({});

  final Map<String, int> counts;

  Vv bump(String device) => Vv({...counts, device: (counts[device] ?? 0) + 1});

  Vv join(Vv other) => Vv({
        for (final k in {...counts.keys, ...other.counts.keys})
          k: (counts[k] ?? 0) > (other.counts[k] ?? 0) ? counts[k]! : other.counts[k]!,
      });

  /// How THIS vector stands against [other]: `before` means other has seen everything this has and more.
  VvOrder compare(Vv other) {
    var less = false, more = false;
    for (final k in {...counts.keys, ...other.counts.keys}) {
      final a = counts[k] ?? 0, b = other.counts[k] ?? 0;
      if (a < b) less = true;
      if (a > b) more = true;
    }
    return switch ((less, more)) {
      (false, false) => VvOrder.equal,
      (true, false) => VvOrder.before,
      (false, true) => VvOrder.after,
      (true, true) => VvOrder.concurrent,
    };
  }

  /// Canonical text, stable across copies (sorted keys); used in digests.
  String get canon => (counts.keys.toList()..sort()).map((k) => '$k=${counts[k]}').join(',');

  Map<String, Object?> toJson() => counts;

  /// Null for anything that is not a sane vector: a hostile peer can send any JSON.
  static Vv? parse(Object? j) {
    if (j is! Map || j.length > 64) return null;
    final out = <String, int>{};
    for (final e in j.entries) {
      final k = e.key, v = e.value;
      if (k is! String || k.isEmpty || k.length > 64 || v is! int || v < 1 || v > 1 << 40) return null;
      out[k] = v;
    }
    return Vv(out);
  }
}
