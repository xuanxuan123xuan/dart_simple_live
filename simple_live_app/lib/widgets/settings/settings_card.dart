import 'package:flutter/material.dart';
import 'package:simple_live_app/app/platform_utils.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';

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
    return GlassSurface(
      role: GlassSurfaceRole.content,
      radius: 14,
      fallbackColor: theme.colorScheme.surface.withAlpha(
        theme.brightness == Brightness.dark ? 176 : 210,
      ),
      fallbackBorder: true,
      child: child,
    );
  }
}
