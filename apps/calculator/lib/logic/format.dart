/// Formats [v] for a 12-significant-digit display: `0.1 + 0.2` shows `0.3`, not `0.30000000000000004`.
/// NaN and infinity (division by zero) show `Error`.
String formatNumber(double v) {
  if (v.isNaN || v.isInfinite) return 'Error';
  if (v == 0) return '0'; // also folds -0.0
  final s = v.toStringAsPrecision(12);
  final e = s.indexOf('e');
  if (e < 0) return _stripZeros(s);
  return '${_stripZeros(s.substring(0, e))}${s.substring(e)}';
}

String _stripZeros(String s) {
  if (!s.contains('.')) return s;
  var r = s.replaceFirst(RegExp(r'0+$'), '');
  if (r.endsWith('.')) r = r.substring(0, r.length - 1);
  return r;
}
