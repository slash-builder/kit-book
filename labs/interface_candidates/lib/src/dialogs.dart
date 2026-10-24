// confirmDialog and promptDialog: the rename / delete pair.
//
// Candidate evidence: ONE app (notepad: `showConfirmDialog` for delete,
// `showPromptDialog` for rename; its (e) section says the rename dialog needed
// its own StatefulWidget to own the text controller). No other demo app asked
// for either. The larger app's dialog use was not counted for this package.

import 'package:flutter/material.dart';

import 'spacing.dart';

/// Asks a yes/no question and returns true only if the person confirmed.
/// Dismissing (Cancel, Escape, tapping the barrier) is false.
///
/// With [destructive] the confirm button uses the theme's error colours AND the
/// safe button, Cancel, gets the initial keyboard focus, so a stray Enter does
/// not delete anything. The words on the buttons carry the meaning ("Delete"),
/// not the colour.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  Key? confirmKey,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        scrollable:
            true, // title and message scroll together at large text scales
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            autofocus: destructive,
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            key: confirmKey,
            autofocus: !destructive,
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return ok == true;
}

/// Asks for one line of text and returns it, or null if cancelled.
///
/// The dialog owns its [TextEditingController] (created when it opens, disposed
/// after its closing animation), so callers need no StatefulWidget. The initial
/// text is pre-selected, so typing replaces it (rename). Enter confirms.
///
/// [validator] gets the current text and returns an error message or null. It
/// runs when the person confirms; if it returns a message the dialog stays open
/// and shows it under the field (exposed to screen readers by the TextField); afterwards it
/// re-runs on every edit. The returned text is exactly what was typed.
Future<String?> promptDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? message,
  String initial = '',
  String? fieldLabel,
  String cancelLabel = 'Cancel',
  String? Function(String text)? validator,
  Key? fieldKey,
  Key? confirmKey,
}) =>
    showDialog<String>(
      context: context,
      builder: (context) => _PromptDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        initial: initial,
        fieldLabel: fieldLabel,
        validator: validator,
        fieldKey: fieldKey,
        confirmKey: confirmKey,
      ),
    );

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.initial,
    required this.fieldLabel,
    required this.validator,
    this.fieldKey,
    this.confirmKey,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final String initial;
  final String? fieldLabel;
  final String? Function(String text)? validator;
  final Key? fieldKey;
  final Key? confirmKey;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial)
        ..selection =
            TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  String? _error;
  var _attempted = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    _attempted = true;
    final error = widget.validator?.call(_text.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _text.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!),
            const SizedBox(height: kGapM)
          ],
          TextField(
            key: widget.fieldKey,
            controller: _text,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
                labelText: widget.fieldLabel, errorText: _error),
            onChanged: (value) {
              if (_attempted) {
                setState(() => _error = widget.validator?.call(value));
              }
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.cancelLabel)),
        FilledButton(
            key: widget.confirmKey,
            onPressed: _submit,
            child: Text(widget.confirmLabel)),
      ],
    );
  }
}
