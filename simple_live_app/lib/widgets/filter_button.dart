import 'package:flutter/material.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';

class FilterButton extends StatelessWidget {
  final bool selected;
  final String text;
  final bool glass;
  final Function()? onTap;
  const FilterButton({
    this.selected = false,
    required this.text,
    this.glass = false,
    this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const radius = 18.0;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 36),
      padding: AppStyle.edgeInsetsH16.copyWith(top: 7, bottom: 7),
      decoration: BoxDecoration(
        color: selected ? colors.primary.withAlpha(24) : Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? colors.primary : Colors.transparent,
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: selected ? colors.primary : colors.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
    if (glass) {
      return GlassSurface(
        role: GlassSurfaceRole.control,
        radius: radius,
        onTap: onTap,
        child: content,
      );
    }
    return Material(
      color: selected
          ? colors.primaryContainer.withAlpha(220)
          : colors.surface.withAlpha(
              theme.brightness == Brightness.dark ? 150 : 190,
            ),
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? colors.primary.withAlpha(150)
              : colors.outlineVariant.withAlpha(130),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
