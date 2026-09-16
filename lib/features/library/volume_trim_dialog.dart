import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/volume_repository.dart';

/// Per-song balancer fix (−12…+12 dB). Applies live while dragging when
/// the song is currently playing — the volume applier reacts to trim
/// edits — and on next play otherwise.
Future<void> showVolumeTrimDialog(
  BuildContext context,
  WidgetRef ref, {
  required String songId,
  required String songTitle,
  required String songArtist,
}) {
  final notifier = ref.read(volumeSettingsProvider.notifier);
  var value = ref.read(volumeSettingsProvider).trimFor(songId);
  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Balance volume'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$songTitle · $songArtist',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    min: minTrimDb,
                    max: maxTrimDb,
                    divisions: 48,
                    value: value,
                    label: '${_fmtDb(value)} dB',
                    onChanged: (v) {
                      setState(() => value = v);
                      notifier.setTrim(songId, v);
                    },
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${_fmtDb(value)} dB',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const Text(
                'Cuts are safer than boosts — loud masters can clip.'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: value == 0
                    ? null
                    : () {
                        setState(() => value = 0);
                        notifier.clearTrim(songId);
                      },
                child: const Text('Reset'),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}

String _fmtDb(double v) =>
    '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}';
