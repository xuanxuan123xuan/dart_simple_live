import 'package:flutter/material.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';

class ShadowCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final Function()? onTap;
  final Color? backgroundColor;
  /// Whether the card should use the liquid-glass renderer.
  ///
  /// Dense scrolling grids can contain many cards at once. Callers that
  /// render those cards can opt into the opaque Material path to avoid
  /// creating a glass surface for every item.
  final bool glassEnabled;
  /// Whether the card should draw the decorative drop shadow.
  final bool shadowEnabled;
  const ShadowCard({
    required this.child,
    this.radius = 14.0,
    this.onTap,
    this.backgroundColor,
    this.glassEnabled = true,
    this.shadowEnabled = true,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderRadius = BorderRadius.circular(radius);
    final fallbackColor = backgroundColor ??
        colorScheme.surface.withAlpha(
          theme.brightness == Brightness.dark ? 184 : 214,
        );
    final card = glassEnabled
        ? GlassSurface(
            role: GlassSurfaceRole.content,
            radius: radius,
            onTap: onTap,
            fallbackColor: fallbackColor,
            child: child,
          )
        : Material(
            color: fallbackColor,
            borderRadius: borderRadius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: borderRadius,
              onTap: onTap,
              child: child,
            ),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(110)),
        boxShadow: shadowEnabled
            ? [
                BoxShadow(
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                  color: Colors.black.withAlpha(
                    theme.brightness == Brightness.dark ? 28 : 18,
                  ),
                ),
              ]
            : const [],
      ),
      child: card,
    );
  }
}
