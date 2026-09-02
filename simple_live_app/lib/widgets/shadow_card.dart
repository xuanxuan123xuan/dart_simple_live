import 'package:flutter/material.dart';

class ShadowCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final Function()? onTap;
  final Color? backgroundColor;
  const ShadowCard({
    required this.child,
    this.radius = 14.0,
    this.onTap,
    this.backgroundColor,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ??
            colorScheme.surface.withAlpha(
              theme.brightness == Brightness.dark ? 184 : 214,
            ),
        borderRadius: borderRadius,
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(110)),
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: const Offset(0, 4),
            color: Colors.black.withAlpha(
              theme.brightness == Brightness.dark ? 28 : 18,
            ),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}
