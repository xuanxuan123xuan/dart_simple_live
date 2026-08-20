import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

/// Compact glass-style volume control intended to float over video content.
class ImmersiveVolumeSlider extends StatelessWidget {
  const ImmersiveVolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onMute,
    this.muteTooltip = "静音",
  });

  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onMute;
  final String muteTooltip;

  static const double width = 184;
  static const double height = 42;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(height / 2));
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xB31A1A1A),
              borderRadius: radius,
              border: Border.all(
                color: Colors.white.withAlpha(28),
                width: 0.75,
              ),
            ),
            child: SizedBox(
              width: width,
              height: height,
              child: Material(
                color: Colors.transparent,
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 40,
                      child: IconButton(
                        tooltip: muteTooltip,
                        onPressed: onMute,
                        padding: EdgeInsets.zero,
                        splashRadius: 18,
                        icon: const Icon(
                          Remix.volume_mute_line,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.5,
                            activeTrackColor: Colors.white.withAlpha(230),
                            inactiveTrackColor: Colors.white.withAlpha(52),
                            thumbColor: Colors.white,
                            overlayColor: Colors.white.withAlpha(24),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                              elevation: 0,
                              pressedElevation: 0,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                          ),
                          child: Slider(
                            value: value.clamp(0, 100).toDouble(),
                            min: 0,
                            max: 100,
                            onChanged: onChanged,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
