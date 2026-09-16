import 'package:flutter/material.dart';

/// Shared playlist name input. Returns the trimmed name, or null when
/// the user cancels. Empty input disables the confirm button.
///
/// The controller is owned by the dialog itself (created in `initState`,
/// disposed with the route) — disposing it from the caller on pop races
/// the exit animation and crashes on rebuild.
Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
  String confirmLabel = 'Create',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      title: title,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  final String title;
  final String? initialValue;
  final String confirmLabel;

  const _NameDialog({
    required this.title,
    this.initialValue,
    required this.confirmLabel,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          hintText: 'Playlist name',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          isDense: true,
        ),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.of(context).pop(v.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton.tonal(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(value.text.trim()),
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
