import 'package:flutter/material.dart';
import 'package:simple_live_app/app/platform_utils.dart';

class SettingsCard extends StatelessWidget {
  final Widget child;
  const SettingsCard({required this.child, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (PlatformUtils.isOhos) {
      // OHOS can stretch a painted card layer far beyond its render box after
      // asynchronous content changes height. Keep settings groups paint-free;
      // their tiles and dividers still provide the visual structure.
      return child;
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
