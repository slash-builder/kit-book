import 'package:application_kit_flutter/application_kit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:interface_candidates/interface_candidates.dart';

import '../logic/calculator.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final calc = Calculator();

  void _do(void Function() f) => setState(f);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final ch = event.character;
    if (k == LogicalKeyboardKey.backspace) {
      _do(calc.backspace);
    } else if (k == LogicalKeyboardKey.escape) {
      _do(calc.clear);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || ch == '=') {
      _do(calc.equals);
    } else if (ch != null && ch.length == 1) {
      switch (ch) {
        case '+':
          _do(() => calc.operator(Op.add));
        case '-':
          _do(() => calc.operator(Op.subtract));
        case '*' || 'x':
          _do(() => calc.operator(Op.multiply));
        case '/':
          _do(() => calc.operator(Op.divide));
        case '.' || ',':
          _do(calc.decimal);
        case '%':
          _do(calc.percent);
        default:
          final d = int.tryParse(ch);
          if (d == null) return KeyEventResult.ignored;
          _do(() => calc.digit(d));
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final ctx = AppContextScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: PageScaffold(
        title: ctx.manifest.name,
        actions: [ModeBadge.forContext(ctx, key: const ValueKey('mode-chip'))],
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(calc.expression, key: const ValueKey('expression'), style: TextStyle(color: scheme.outline, fontSize: 18)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(calc.display, key: const ValueKey('display'), style: const TextStyle(fontSize: 56)),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(flex: 5, child: _keypad()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keypad() {
    Widget k(String label, VoidCallback onTap, {String? id, Color? bg}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: FilledButton.tonal(
              key: ValueKey('key-${id ?? label}'),
              style: FilledButton.styleFrom(backgroundColor: bg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => _do(onTap),
              child: Text(label, style: const TextStyle(fontSize: 24)),
            ),
          ),
        );
    Widget d(int n) => k('$n', () => calc.digit(n));
    final opBg = Theme.of(context).colorScheme.primaryContainer;
    Widget op(String label, Op o, String id) => k(label, () => calc.operator(o), id: id, bg: opBg);
    Widget row(List<Widget> c) => Expanded(child: Row(children: c));
    return Column(children: [
      row([k('AC', calc.clear, id: 'clear'), k('+/-', calc.toggleSign, id: 'sign'), k('%', calc.percent, id: 'percent'), op('÷', Op.divide, 'divide')]),
      row([d(7), d(8), d(9), op('×', Op.multiply, 'multiply')]),
      row([d(4), d(5), d(6), op('−', Op.subtract, 'subtract')]),
      row([d(1), d(2), d(3), op('+', Op.add, 'add')]),
      row([k('⌫', calc.backspace, id: 'backspace'), d(0), k('.', calc.decimal, id: 'decimal'), k('=', calc.equals, id: 'equals', bg: opBg)]),
    ]);
  }
}
