import 'package:app_context_kit/app_context_kit.dart' show SessionSettings;

/// The one setting this app has, in the Kit's ConfigStore (through a session overlay for when the file is damaged).
class Settings {
  Settings(this._config);
  final SessionSettings _config;

  static const minFont = 10.0, maxFont = 40.0, defaultFont = 16.0, step = 2.0;

  bool get readOnly => _config.readOnly;

  double get fontSize => _config.get<double>('fontSize', defaultFont).clamp(minFont, maxFont);
  set fontSize(double v) => _config.set('fontSize', v.clamp(minFont, maxFont));
}
