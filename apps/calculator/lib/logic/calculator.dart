import 'format.dart';

enum Op {
  add('+'),
  subtract('-'),
  multiply('x'),
  divide('/');

  const Op(this.symbol);
  final String symbol;

  double apply(double a, double b) => switch (this) {
        Op.add => a + b,
        Op.subtract => a - b,
        Op.multiply => a * b,
        Op.divide => b == 0 ? double.nan : a / b,
      };
}

/// A basic four-function calculator with the usual immediate-execution behaviour (`2 + 3 x` shows 5).
/// Pure Dart: the display is always a string, and the value used in the next step is the displayed value,
/// so what the person sees is what is calculated.
class Calculator {
  static const maxDigits = 12;

  String _entry = '0';
  double? _acc;
  Op? _pending;
  bool _typing = true; // false when the display shows a result or the accumulator
  bool _error = false;

  /// What the main display shows.
  String get display => _error ? 'Error' : _entry;

  /// The small line above the display: the accumulator and the pending operator (`12 +`).
  String get expression => _pending == null || _acc == null ? '' : '${formatNumber(_acc!)} ${_pending!.symbol}';

  bool get hasError => _error;

  double get _value => double.parse(_entry);

  void digit(int d) {
    assert(d >= 0 && d <= 9);
    if (_error) clear();
    if (!_typing) {
      _entry = '$d';
      _typing = true;
      return;
    }
    if (_digitCount(_entry) >= maxDigits) return;
    _entry = (_entry == '0') ? '$d' : (_entry == '-0' ? '-$d' : '$_entry$d');
  }

  void decimal() {
    if (_error) clear();
    if (!_typing) {
      _entry = '0.';
      _typing = true;
      return;
    }
    if (_entry.contains('.') || _entry.contains('e')) return;
    if (_digitCount(_entry) >= maxDigits) return;
    _entry = '$_entry.';
  }

  void operator(Op op) {
    if (_error) return;
    if (_pending != null && _typing) {
      _commit(_pending!.apply(_acc!, _value));
      if (_error) return;
    } else if (_pending == null) {
      _acc = _value;
    }
    _pending = op;
    _typing = false;
  }

  void equals() {
    if (_error || _pending == null) return;
    final b = _typing ? _value : _acc!; // `2 + =` uses the accumulator as the second operand
    final r = _pending!.apply(_acc!, b);
    _pending = null;
    _acc = null;
    _commit(r);
  }

  void clear() {
    _entry = '0';
    _acc = null;
    _pending = null;
    _typing = true;
    _error = false;
  }

  void backspace() {
    if (_error) {
      clear();
      return;
    }
    if (!_typing) return; // a result is not edited digit by digit
    var s = _entry.substring(0, _entry.length - 1);
    if (s.isEmpty || s == '-') s = '0';
    _entry = s;
  }

  void toggleSign() {
    if (_error) return;
    if (!_typing && _pending != null) {
      // The display shows the accumulator after an operator; the sign key starts the second operand as -0.
      _entry = '-0';
      _typing = true;
      return;
    }
    if (_entry == '0') return;
    _entry = _entry.startsWith('-') ? _entry.substring(1) : '-$_entry';
  }

  /// `50 %` is 0.5. After `+` or `-` it is a percentage of the accumulator (`200 + 10 %` is 200 + 20).
  void percent() {
    if (_error) return;
    final relative = (_pending == Op.add || _pending == Op.subtract) && _acc != null;
    final v = relative ? _acc! * _value / 100 : _value / 100;
    _setEntry(v);
    _typing = _pending != null; // with an operator pending, the percentage is the second operand
  }

  void _commit(double v) {
    _setEntry(v);
    _typing = false;
    if (!_error) _acc = _value;
  }

  void _setEntry(double v) {
    final s = formatNumber(v);
    if (s == 'Error') {
      _error = true;
      _entry = '0';
      _acc = null;
      _pending = null;
    } else {
      _entry = s;
    }
  }

  static int _digitCount(String s) => s.replaceAll(RegExp(r'[^0-9]'), '').length;
}
