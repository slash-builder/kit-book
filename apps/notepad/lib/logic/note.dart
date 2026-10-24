/// One note. Immutable; edits make a new value.
class Note {
  const Note({required this.id, required this.title, required this.body, required this.createdAt, required this.updatedAt});

  final String id; // also the file name stem
  final String title;
  final String body;
  final DateTime createdAt, updatedAt;

  static final idPattern = RegExp(r'^[a-z0-9]{4,40}$');

  Note copyWith({String? title, String? body, DateTime? updatedAt}) =>
      Note(id: id, title: title ?? this.title, body: body ?? this.body, createdAt: createdAt, updatedAt: updatedAt ?? this.updatedAt);

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  /// Throws [FormatException] when the data is not a note.
  static Note fromJson(Object? json) {
    if (json is! Map) throw const FormatException('a note must be a JSON object');
    final id = json['id'], title = json['title'], body = json['body'], created = json['createdAt'], updated = json['updatedAt'];
    if (id is! String || !idPattern.hasMatch(id)) throw const FormatException('bad id');
    if (title is! String) throw const FormatException('title is not text');
    if (body is! String) throw const FormatException('body is not text');
    if (created is! String || updated is! String) throw const FormatException('dates are not text');
    return Note(id: id, title: title, body: body, createdAt: DateTime.parse(created), updatedAt: DateTime.parse(updated));
  }
}
