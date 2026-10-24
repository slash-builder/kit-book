import 'package:flutter_test/flutter_test.dart';
import 'package:interface_candidates/interface_candidates.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 12, 0, 0);
  String ago(Duration d) => relativeTime(now.subtract(d), now: now);
  String ahead(Duration d) => relativeTime(now.add(d), now: now);

  group('past', () {
    for (final (duration, expected) in <(Duration, String)>[
      (Duration.zero, 'just now'),
      (const Duration(seconds: 1), 'just now'),
      (const Duration(seconds: 59), 'just now'),
      (const Duration(milliseconds: 59999), 'just now'),
      (const Duration(minutes: 1), '1 minute ago'),
      (const Duration(minutes: 1, seconds: 59), '1 minute ago'),
      (const Duration(minutes: 2), '2 minutes ago'),
      (const Duration(minutes: 59, seconds: 59), '59 minutes ago'),
      (const Duration(hours: 1), '1 hour ago'),
      (const Duration(hours: 2, minutes: 59), '2 hours ago'),
      (const Duration(hours: 23, minutes: 59), '23 hours ago'),
      (const Duration(days: 1), '1 day ago'),
      (const Duration(days: 6, hours: 23), '6 days ago'),
      (const Duration(days: 7), '1 week ago'),
      (const Duration(days: 13), '1 week ago'),
      (const Duration(days: 14), '2 weeks ago'),
      (const Duration(days: 29), '4 weeks ago'),
      (const Duration(days: 30), '1 month ago'),
      (const Duration(days: 59), '1 month ago'),
      (const Duration(days: 60), '2 months ago'),
      (const Duration(days: 364), '12 months ago'),
      (const Duration(days: 365), '1 year ago'),
      (const Duration(days: 729), '1 year ago'),
      (const Duration(days: 730), '2 years ago'),
      (const Duration(days: 3650), '10 years ago'),
    ]) {
      test('$duration ago -> "$expected"',
          () => expect(ago(duration), expected));
    }
  });

  group('future', () {
    for (final (duration, expected) in <(Duration, String)>[
      (const Duration(seconds: 1), 'just now'), // clock skew, not a countdown
      (const Duration(seconds: 59), 'just now'),
      (const Duration(minutes: 1), 'in 1 minute'),
      (const Duration(minutes: 5), 'in 5 minutes'),
      (const Duration(hours: 1), 'in 1 hour'),
      (const Duration(days: 3), 'in 3 days'),
      (const Duration(days: 14), 'in 2 weeks'),
      (const Duration(days: 400), 'in 1 year'),
    ]) {
      test('$duration ahead -> "$expected"',
          () => expect(ahead(duration), expected));
    }
  });

  group('edges', () {
    test('exactly now is "just now"',
        () => expect(relativeTime(now, now: now), 'just now'));

    test(
        'the boundary between "just now" and a minute is exactly 60 s, in both directions',
        () {
      expect(ago(const Duration(seconds: 59, milliseconds: 999)), 'just now');
      expect(ago(const Duration(seconds: 60)), '1 minute ago');
      expect(ahead(const Duration(seconds: 59, milliseconds: 999)), 'just now');
      expect(ahead(const Duration(seconds: 60)), 'in 1 minute');
    });

    test('singular and plural', () {
      expect(ago(const Duration(minutes: 1)), isNot(contains('minutes')));
      expect(ago(const Duration(minutes: 2)), contains('minutes'));
    });

    test('compares instants: a UTC time against a local "now" and the reverse',
        () {
      final utcTime = DateTime.utc(2026, 10, 21, 11, 0);
      final localNow = now.toLocal();
      expect(relativeTime(utcTime, now: localNow), '1 hour ago');
      expect(relativeTime(utcTime.toLocal(), now: now), '1 hour ago');
    });

    test('across a month and a year boundary (instants, not calendar fields)',
        () {
      expect(
          relativeTime(DateTime.utc(2025, 12, 31, 23, 59),
              now: DateTime.utc(2026, 1, 1, 0, 1)),
          '2 minutes ago');
    });

    test('now defaults to the current time', () {
      expect(relativeTime(DateTime.now()), 'just now');
      expect(
          relativeTime(
              DateTime.now().subtract(const Duration(hours: 3, minutes: 1))),
          '3 hours ago');
    });

    test(
        'never says "0 <unit>", "-1" or "1 minutes" for any whole second across 400 days',
        () {
      final bad = RegExp(r'(^| )0 |-|\b1 \w+s\b');
      for (var s = 0; s < 400 * 86400; s += 997) {
        expect(bad.hasMatch(ago(Duration(seconds: s))), isFalse,
            reason: 'past $s s: ${ago(Duration(seconds: s))}');
        expect(bad.hasMatch(ahead(Duration(seconds: s))), isFalse,
            reason: 'future $s s: ${ahead(Duration(seconds: s))}');
      }
    });
  });
}
