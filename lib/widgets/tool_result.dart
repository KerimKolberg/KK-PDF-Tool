import 'package:flutter/material.dart';

int _bannerId = 0;

/// Shows [message] as a banner at the top of the screen (so it never covers
/// buttons or options at the bottom) and hides it again after a few seconds.
void showResultBanner(ScaffoldMessengerState messenger, String message) {
  final id = ++_bannerId;
  messenger
    ..clearMaterialBanners()
    ..showMaterialBanner(MaterialBanner(
      leading: const Icon(Icons.check_circle_outline),
      content: Text(message),
      actions: [
        TextButton(onPressed: messenger.hideCurrentMaterialBanner, child: const Text('OK')),
      ],
    ));
  Future<void>.delayed(const Duration(seconds: 6), () {
    if (id == _bannerId) messenger.hideCurrentMaterialBanner();
  });
}

/// After a successful save: reopen the same tool fresh (ready for the next
/// file) instead of leaving it, and show where the result was saved.
void finishTool(BuildContext context, Widget tool, String message) {
  final messenger = ScaffoldMessenger.of(context);
  Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => tool,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  ));
  WidgetsBinding.instance.addPostFrameCallback((_) => showResultBanner(messenger, message));
}
