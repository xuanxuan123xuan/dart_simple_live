import 'package:flutter/material.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/platform_utils.dart';

class SettingsCard extends StatelessWidget {
  final Widget child;
  const SettingsCard({required this.child, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (PlatformUtils.isOhos) {
      // HarmonyOS can lose the lower part of a tall, dynamically growing
      // clipped translucent Material layer. Keep the proven non-clipping
      // card path there.
      return Material(
        color: theme.brightness == Brightness.dark
            ? Colors.grey.withAlpha(50)
            : Colors.white70,
        shape: RoundedRectangleBorder(
          borderRadius: AppStyle.radius8,
          side: BorderSide(color: Colors.grey.withAlpha(25)),
        ),
        child: Container(
          decoration: BoxDecoration(borderRadius: AppStyle.radius8),
          child: child,
        ),
      );
    }
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
