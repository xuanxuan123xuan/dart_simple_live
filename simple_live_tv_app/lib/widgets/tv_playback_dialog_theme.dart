import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared visual language for TV playback dialogs.
abstract final class TvPlaybackDialogTheme {
  static const Color _navy = Color(0xff172337);
  static const Color _navyLight = Color(0xff202f45);
  static const Color _surface = Color(0xff202e42);
  static const Color _outline = Color(0x36ffffff);
  static const double radius = 20;

  static ThemeData themed(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final focusSide = WidgetStateProperty.resolveWith<BorderSide>((states) {
      return states.contains(WidgetState.focused)
          ? BorderSide(color: accent, width: 2.4)
          : BorderSide.none;
    });

    return theme.copyWith(
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.selected)
              ? accent
              : Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: Color(0x99ffffff), width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: const Color(0x12ffffff),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: Color(0xbfffffff)),
        hintStyle: const TextStyle(color: Color(0x80ffffff)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 2.4),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 48)),
          shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
          side: focusSide,
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 48)),
          shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
          side: focusSide,
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 18),
          ),
        ),
      ),
    );
  }

  static Color get surfaceColor => _surface;
  static Color get outlineColor => _outline;

  static Color selectedSurface(Color accent) => accent.withValues(alpha: .13);

  static Size dialogSize(
    BuildContext context, {
    required double maxWidth,
    required double maxHeight,
  }) {
    final size = MediaQuery.sizeOf(context);
    final horizontalInset = size.width < 800 ? 20.0 : 40.0;
    return Size(
      math.min(maxWidth, math.max(280, size.width - horizontalInset * 2)),
      math.min(maxHeight, math.max(320, size.height - 48)),
    );
  }
}

class TvPlaybackDialogSurface extends StatelessWidget {
  const TvPlaybackDialogSurface({
    super.key,
    required this.maxWidth,
    required this.maxHeight,
    required this.child,
  });

  final double maxWidth;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = TvPlaybackDialogTheme.dialogSize(
      context,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
    final mediaSize = MediaQuery.sizeOf(context);

    return Theme(
      data: TvPlaybackDialogTheme.themed(context),
      child: Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.symmetric(
          horizontal: mediaSize.width < 800 ? 20 : 40,
          vertical: 24,
        ),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TvPlaybackDialogTheme._navyLight,
                  TvPlaybackDialogTheme._navy,
                  Color(0xff1b2b40),
                ],
              ),
              borderRadius: BorderRadius.circular(TvPlaybackDialogTheme.radius),
              border: Border.all(color: const Color(0x38ffffff)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 32,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TvPlaybackDialogTheme.radius),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class TvPlaybackDialogHeader extends StatelessWidget {
  const TvPlaybackDialogHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: .34)),
          ),
          child: Icon(icon, color: accent, size: 25),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xbfffffff),
                    ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 16),
          trailing!,
        ],
      ],
    );
  }
}

class TvDialogFocusableSurface extends StatefulWidget {
  const TvDialogFocusableSurface({
    super.key,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.disabled = false,
    this.autofocus = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.minHeight = 48,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  final bool disabled;
  final bool autofocus;
  final EdgeInsetsGeometry padding;
  final double minHeight;

  @override
  State<TvDialogFocusableSurface> createState() =>
      _TvDialogFocusableSurfaceState();
}

class _TvDialogFocusableSurfaceState extends State<TvDialogFocusableSurface> {
  late final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final borderColor = _focused
        ? accent
        : widget.selected
            ? accent.withValues(alpha: .72)
            : TvPlaybackDialogTheme.outlineColor;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (value) => setState(() => _focused = value),
        onTap: widget.disabled ? null : widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: BoxConstraints(minHeight: widget.minHeight),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.selected
                ? TvPlaybackDialogTheme.selectedSurface(accent)
                : TvPlaybackDialogTheme.surfaceColor.withValues(alpha: .66),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: _focused ? 2.4 : (widget.selected ? 1.6 : 1),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
