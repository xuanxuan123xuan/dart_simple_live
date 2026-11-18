import 'package:flutter/material.dart';

/// A single 10-foot UI control with a visible focus ring for Siri Remote.
class TvButton extends StatefulWidget {
  const TvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.autofocus = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool selected;
  final bool autofocus;
  @override
  State<TvButton> createState() => _TvButtonState();
}

class _TvButtonState extends State<TvButton> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
        autofocus: widget.autofocus,
        onFocusChange: (v) => setState(() => focused = v),
        child: Builder(
          builder: (context) => InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              padding: const EdgeInsets.symmetric(horizontal: 23, vertical: 15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: focused || widget.selected
                    ? const Color(0xFF2855A4)
                    : const Color(0xFF1F2635),
                border: Border.all(
                  color: focused ? Colors.white : Colors.white24,
                  width: focused ? 2.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 23),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
