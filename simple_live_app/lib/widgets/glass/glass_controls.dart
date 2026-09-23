import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid_glass_widgets;
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';

/// App-wide adapters for interactive glass controls. They keep the fallback
/// path accessible while giving every toolbar action the same material.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({required this.icon, required this.onPressed, this.tooltip, this.size = 44, super.key});
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final quality = AppGlassController.qualityOf(context, role: GlassSurfaceRole.control);
    final button = quality == null
        ? IconButton(onPressed: onPressed, icon: icon)
        : liquid_glass_widgets.GlassIconButton(
            icon: icon,
            onPressed: onPressed,
            size: size,
            quality: quality,
            useOwnLayer: true,
            shape: liquid_glass_widgets.GlassIconButtonShape.roundedSquare,
            borderRadius: 14,
            semanticLabel: tooltip,
          );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class GlassSettingsSurface extends StatelessWidget {
  const GlassSettingsSurface({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => GlassSurface(
        role: GlassSurfaceRole.content,
        radius: 14,
        padding: EdgeInsets.zero,
        child: child,
      );
}
