// relativeTime: "3 minutes ago".
//
// Candidate evidence: ONE app (launcher listed a "relative-time formatter" in
// its (e) section; its actual code is `formatUptime`, a Duration formatter,
// which this does NOT replace). Pure and locale-neutral English.

/// Formats [time] relative to [now] (default: the current time) in English:
/// "just now", "5 minutes ago", "2 hours ago", "3 days ago", "2 weeks ago",
/// "4 months ago", "1 year ago"; and for times in the future "in 5 minutes".
///
/// Rules (all by whole units, rounded down):
///  * under a minute, past OR future: "just now" (a future time a few seconds
///    ahead is almost always clock skew between machines, so it is not shown as
///    "in 12 seconds"; this is not a countdown formatter);
///  * under an hour: minutes; under a day: hours; under 7 days: days;
///    under 30 days: weeks; under 365 days: months (30 days each); then years
///    (365 days each);
///  * "1 minute", not "1 minutes".
///
/// Instants are compared, so a UTC [time] and a local [now] are fine.
/// English only; it is not localised and does not claim to be.
String relativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final difference = reference.difference(time);
  final inFuture = difference.isNegative;
  final span = inFuture ? -difference : difference;

  if (span < const Duration(minutes: 1)) return 'just now';

  final (int count, String unit) = switch (span) {
    < const Duration(hours: 1) => (span.inMinutes, 'minute'),
    < const Duration(days: 1) => (span.inHours, 'hour'),
    < const Duration(days: 7) => (span.inDays, 'day'),
    < const Duration(days: 30) => (span.inDays ~/ 7, 'week'),
    < const Duration(days: 365) => (span.inDays ~/ 30, 'month'),
    _ => (span.inDays ~/ 365, 'year'),
  };
  final phrase = '$count $unit${count == 1 ? '' : 's'}';
  return inFuture ? 'in $phrase' : '$phrase ago';
}
