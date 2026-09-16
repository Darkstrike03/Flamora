import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connectivity/online_mode_repository.dart';

/// Online/offline switch for the Home header. Pure preference for now
/// (see [onlineModeProvider]) — flips the icon with snackbar feedback.
class OnlineToggleButton extends ConsumerWidget {
  const OnlineToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineModeProvider);
    return IconButton(
      tooltip: online ? 'Online — tap to go offline' : 'Offline — tap to go online',
      onPressed: () async {
        await ref.read(onlineModeProvider.notifier).toggle();
        if (!context.mounted) return;
        final nowOnline = ref.read(onlineModeProvider);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(nowOnline
                  ? 'Back online.'
                  : 'Offline mode — local only.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      },
      icon: Icon(online ? Icons.wifi_rounded : Icons.wifi_off_rounded),
    );
  }
}
