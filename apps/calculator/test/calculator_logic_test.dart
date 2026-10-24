import 'package:calculator/logic/calculator.dart';
import 'package:calculator/logic/format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Presses a sequence like `12+3=`; `~` is the sign key, `%` percent, `C` clear, `<` backspace, `.` decimal.
Calculator press(String keys, [Calculator? c]) {
  final calc = c ?? Calculator();
  for (final ch in keys.split('')) {
    switch (ch) {
      case '+':
        calc.operator(Op.add);
      case '-':
        calc.operator(Op.subtract);
      case '*':
        calc.operator(Op.multiply);
      case '/':
        calc.operator(Op.divide);
      case '=':
        calc.equals();
      case '.':
        calc.decimal();
      case '%':
        calc.percent();
      case '~':
        calc.toggleSign();
      case 'C':
        calc.clear();
      case '<':
        calc.backspace();
      default:
        calc.digit(int.parse(ch));
    }
  }
  return calc;
}

void main() {
  group('formatNumber', () {
    test('hides floating point noise', () {
      expect(formatNumber(0.1 + 0.2), '0.3');
      expect(formatNumber(1 / 3), '0.333333333333');
      expect(formatNumber(2 / 3), '0.666666666667');
    });
    test('integers and zero', () {
      expect(formatNumber(42), '42');
      expect(formatNumber(-0.0), '0');
      expect(formatNumber(100), '100');
      expect(formatNumber(1200), '1200');
    });
    test('large and small values use an exponent without trailing zeros', () {
      expect(formatNumber(1e15), '1e+15');
      expect(formatNumber(1.5e-9), '1.5e-9');
    });
    test('nan and infinity are Error', () {
      expect(formatNumber(double.nan), 'Error');
      expect(formatNumber(double.infinity), 'Error');
    });
  });

  group('Calculator', () {
    test('starts at 0', () => expect(Calculator().display, '0'));
    test('digits and leading zero', () {
      expect(press('007').display, '7');
      expect(press('120').display, '120');
    });
    test('decimals', () {
      expect(press('.5').display, '0.5');
      expect(press('1.2.3').display, '1.23');
      expect(press('0.1+0.2=').display, '0.3');
    });
    test('four operations', () {
      expect(press('7+5=').display, '12');
      expect(press('7-5=').display, '2');
      expect(press('7*5=').display, '35');
      expect(press('7/2=').display, '3.5');
    });
    test('chains evaluate left to right as they are entered', () {
      final c = press('2+3*');
      expect(c.display, '5');
      expect(c.expression, '5 x');
      expect(press('2+3*4=').display, '20');
    });
    test('changing the operator replaces the pending one', () {
      expect(press('2+*3=').display, '6');
    });
    test('equals with no second operand uses the accumulator', () {
      expect(press('4+=').display, '8');
    });
    test('equals with nothing pending does nothing', () {
      expect(press('9=').display, '9');
    });
    test('a digit after a result starts a new number', () {
      final c = press('2+2=');
      expect(c.display, '4');
      expect(press('7', c).display, '7');
    });
    test('an operator after a result continues from it', () {
      expect(press('2+2=*3=').display, '12');
    });
    test('division by zero is an error that clears on the next key', () {
      final c = press('5/0=');
      expect(c.display, 'Error');
      expect(c.hasError, isTrue);
      expect(press('3', c).display, '3');
      expect(c.hasError, isFalse);
    });
    test('operators are ignored while in error', () {
      final c = press('5/0=');
      press('+', c);
      expect(c.display, 'Error');
    });
    test('clear resets everything', () {
      final c = press('2+3C');
      expect(c.display, '0');
      expect(c.expression, '');
      expect(press('4=', c).display, '4');
    });
    test('backspace edits the number being typed', () {
      expect(press('123<').display, '12');
      expect(press('1<').display, '0');
      expect(press('1.5<<').display, '1');
      expect(press('1~<').display, '0');
    });
    test('backspace does not edit a result', () {
      expect(press('2+2=<').display, '4');
    });
    test('sign toggle', () {
      expect(press('5~').display, '-5');
      expect(press('5~~').display, '5');
      expect(press('0~').display, '0');
      expect(press('2+3=~').display, '-5');
      expect(press('5~*2=').display, '-10');
    });
    test('sign after an operator starts the second operand negative', () {
      expect(press('5+~3=').display, '2');
    });
    test('percent', () {
      expect(press('50%').display, '0.5');
      expect(press('200+10%=').display, '220');
      expect(press('200-10%=').display, '180');
      expect(press('200*10%=').display, '20');
    });
    test('digit count is limited', () {
      expect(press('1234567890123').display, '123456789012');
    });
    test('large results keep working through the exponent form', () {
      final c = press('999999999999*999999999999=');
      expect(c.display, contains('e+'));
      expect(press('/2=', c).hasError, isFalse);
    });
    test('a long division shows 12 digits', () {
      expect(press('1/3=').display, '0.333333333333');
    });
  });
}
