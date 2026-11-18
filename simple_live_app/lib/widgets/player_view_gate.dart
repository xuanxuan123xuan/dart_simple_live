import 'package:flutter/widgets.dart';

/// Defers creation of a native video subtree until its owner is ready.
class PlayerViewGate extends StatelessWidget {
  const PlayerViewGate({
    required this.ready,
    required this.readyBuilder,
    required this.waitingBuilder,
    super.key,
  });

  final bool ready;
  final WidgetBuilder readyBuilder;
  final WidgetBuilder waitingBuilder;

  @override
  Widget build(BuildContext context) {
    return ready ? readyBuilder(context) : waitingBuilder(context);
  }
}
