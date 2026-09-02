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
      // Avoid Material entirely: the OHOS renderer can leave an oversized
      // translucent Material surface after a settings card changes height.
      return Container(
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? Colors.grey.withAlpha(50)
              : Colors.white70,
          borderRadius: AppStyle.radius8,
          border: Border.all(color: Colors.grey.withAlpha(25)),
        ),
        child: child,
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
