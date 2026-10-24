import 'package:application_kit_flutter/application_kit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the bundled app.json parses into the manifest the spec expects', (t) async {
    final m = await AppKit.loadManifest('app.json');
    expect(m.id, 'dev.demo.calc');
    expect(m.envPrefix, 'CALC');
    expect(m.venue.mode, 'off');
  });
}
