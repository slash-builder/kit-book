import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_rust/core/fake_notes_core.dart';

import 'support/scenarios.dart';

/// The sync scenarios on the in-memory fake core: no native library, no Rust build. The same scenarios run on the real core
/// in integration_test/.
void main() {
  final s = Scenarios(File('app.json').readAsStringSync(), (ctx) async => FakeNotesCore(device: ctx.peerDevice, instance: ctx.instance));

  test('two copies converge on notes made, edited and deleted on either side', s.convergence);

  test('a one-byte edit of a 2 MiB note moves a small part of it, in parts', () async {
    final (cold, edit, body) = await s.smallEdit(2 * 1024 * 1024);
    // ignore: avoid_print
    print('fake core: cold ${cold}B, edit ${edit}B of ${body}B');
  });

  test('a tampered block is refused, nothing is stored, and an honest retry works', s.tamperedBlockIsRefused);

  test('a conflict keeps both versions and both copies end up the same', s.conflictKeepsBothAndConverges);
}
