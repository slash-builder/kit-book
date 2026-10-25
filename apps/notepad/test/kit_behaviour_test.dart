// These tests pin what the Kit does NOW where it surprised this app in round 1 (spec section 5 items 3, 4, 9). Round 1 pinned the
// old defects; each assertion below is the replacement behaviour, and the workarounds they justified were deleted from lib/kit_gaps/.
import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';
import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('notepad-kit-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final manifest = AppManifest.fromJson({'id': 'dev.demo.notepad', 'name': 'Notepad', 'version': '0.1.0'});
  Map<String, String> env() => {'APP_CONTEXT_SCRATCH': tmp.path};
  File cfg() => File('${tmp.path}/dev.demo.notepad/config/config.json');

  Future<AppContext> open() => AppContext.open(manifest, env: env(), platform: 'linux', home: '/x', announce: false);

  test('the first set() on a damaged config throws DamagedConfigError and the file is byte-for-byte unchanged', () async {
    cfg().createSync(recursive: true);
    cfg().writeAsStringSync('{"fontSize": 20, "keepMe": true, ');
    final before = cfg().readAsBytesSync();
    final ctx = await open();
    expect(ctx.config.problem, isNotNull);
    expect(ctx.config.isDamaged, isTrue);
    expect(() => ctx.config.set('fontSize', 18), throwsA(isA<DamagedConfigError>()));
    expect(() => ctx.config.save(), throwsA(isA<DamagedConfigError>()));
    expect(cfg().readAsBytesSync(), before);
    await ctx.close();
    expect(cfg().readAsBytesSync(), before);
  });

  test('setAsideCorrupt() moves a damaged file to config.json.corrupt and writes work again', () async {
    cfg().createSync(recursive: true);
    cfg().writeAsStringSync('{"fontSize": 20, ');
    final ctx = await open();
    final moved = ctx.config.setAsideCorrupt();
    expect(moved!.path, endsWith('config.json.corrupt'));
    expect(moved.readAsStringSync(), '{"fontSize": 20, ');
    ctx.config.set('fontSize', 18);
    expect(ctx.config.isDamaged, isFalse);
    expect(cfg().readAsStringSync(), contains('18'));
    await ctx.close();
  });

  test('ConfigStore.get<double> reads a whole number as a double', () async {
    cfg().createSync(recursive: true);
    cfg().writeAsStringSync('{"fontSize": 18}');
    final ctx = await open();
    expect(ctx.config.get<double>('fontSize', 14.0), 18.0);
    expect(ctx.config.get<int>('fontSize', 14), 18);
    await ctx.close();
  });

  test('ConfigStore.get<List<int>> still returns the fallback because decoded lists are List<dynamic>', () async {
    cfg().createSync(recursive: true);
    cfg().writeAsStringSync('{"recent": [1, 2]}');
    final ctx = await open();
    expect(ctx.config.get<List<int>>('recent', const []), isEmpty);
    expect(ctx.config.get<List<dynamic>>('recent', const []), [1, 2]);
    await ctx.close();
  });

  test('a config.json that is not valid UTF-8 no longer prevents the app starting; it is reported and left alone', () async {
    cfg().createSync(recursive: true);
    cfg().writeAsBytesSync([0xff, 0xfe, 0x80]);
    final ctx = await open();
    expect(ctx.config.isDamaged, isTrue);
    expect(ctx.notes.where((n) => n.severity == NoteSeverity.warning && n.text.startsWith('Settings:')), hasLength(1));
    expect(cfg().readAsBytesSync(), [0xff, 0xfe, 0x80]);
    await ctx.close();
  });

  test('AppContext.close is idempotent: onClose callbacks run once however often it is called', () async {
    final ctx = await open();
    var runs = 0;
    ctx.onClose(() => runs++);
    await ctx.close();
    await ctx.close();
    expect(runs, 1);
  });

  test('AppContext.run still closes the moment the body returns, which is why Flutter apps use AppContextKit.run instead', () async {
    var closedWhileAppStillRunning = false;
    await AppContext.run(manifest, (ctx) async {
      ctx.onClose(() => closedWhileAppStillRunning = true);
      // runApp(...) would be here and returns at once
    }, env: env(), platform: 'linux', home: '/x', announce: false);
    expect(closedWhileAppStillRunning, isTrue);
  });

  test('ctx.notes carries the Venue status line as an info note, which NotesBanner hides', () async {
    final ctx = await open();
    expect(ctx.noteTexts, [ctx.venue.description]);
    expect(ctx.notes.single.severity, NoteSeverity.info);
    expect(NotesBanner.visibleOf(ctx.notes), isEmpty);
    await ctx.close();
  });
}
