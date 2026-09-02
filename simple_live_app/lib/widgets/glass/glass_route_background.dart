import 'package:flutter/material.dart';

/// Opaque route backdrop with static theme-colour highlights. Route scaffolds
/// may be transparent without exposing the previous route underneath.
class GlassRouteBackground extends StatelessWidget {
  const GlassRouteBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return ColoredBox(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primary.withAlpha(dark ? 46 : 30),
              colors.surface,
              colors.tertiary.withAlpha(dark ? 38 : 24),
            ],
            stops: const [0, 0.52, 1],
          ),
        ),
        child: child,
      ),
    );
  }
}
