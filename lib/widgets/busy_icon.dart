import 'package:flutter/material.dart';

/// A button icon that turns into a small spinner while [busy]. The spinner
/// takes the button's own text colour, so it is visible on every button
/// style and in both themes.
class BusyIcon extends StatelessWidget {
  final bool busy;
  final Widget child;

  const BusyIcon({super.key, required this.busy, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!busy) return child;
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: IconTheme.of(context).color),
    );
  }
}
