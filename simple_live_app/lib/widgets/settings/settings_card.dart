import 'package:flutter/material.dart';

class SettingsCard extends StatelessWidget {
  final Widget child;
  const SettingsCard({required this.child, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(14);
    return Material(
      color: theme.colorScheme.surface.withAlpha(
        theme.brightness == Brightness.dark ? 176 : 210,
      ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(105),
        ),
      ),
      child: child,
    );
  }
}
