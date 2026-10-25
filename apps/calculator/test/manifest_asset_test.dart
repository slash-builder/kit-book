import 'package:app_context_kit_flutter/app_context_kit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the bundled app.json parses into the manifest the spec expects', (t) async {
    final m = await AppContextKit.loadManifest('app.json');
    expect(m.id, 'com.slashbuilder.demo.calc');
    expect(m.envPrefix, 'CALC');
    expect(m.venue.mode, 'off');
  });
}
