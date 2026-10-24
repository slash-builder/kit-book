import 'package:application_kit/application_kit.dart' show SessionSettings;

import 'game.dart';

/// The two settings this game has, kept in the Kit's ConfigStore (through a session overlay for when the file is damaged).
class Settings {
  Settings(this._config);
  final SessionSettings _config;

  bool get readOnly => _config.readOnly;

  Difficulty get difficulty {
    final name = _config.get<String>('difficulty', Difficulty.beginner.name);
    return Difficulty.values.where((d) => d.name == name).firstOrNull ?? Difficulty.beginner;
  }

  set difficulty(Difficulty d) => _config.set('difficulty', d.name);

  bool get questionMarks => _config.get<bool>('questionMarks', false);
  set questionMarks(bool v) => _config.set('questionMarks', v);
}
