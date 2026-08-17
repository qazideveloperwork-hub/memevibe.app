import 'package:flutter/material.dart';

/// Wraps [child] with the press-down scale feedback used throughout the
/// Stitch mockups (`active:scale-95 transition-transform`).
class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.95,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<TapScale> createState() => _TapScaleState();
}

// Below this gap between taps, treat repeats as an accidental double-tap
// (e.g. on a card that navigates) rather than two separate intents — avoids
// firing the same push/action twice before the first has registered.
const _debounce = Duration(milliseconds: 500);

class _TapScaleState extends State<TapScale> {
  bool _pressed = false;
  DateTime? _lastActivation;

  void _setPressed(bool value) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    setState(() => _pressed = value);
  }

  bool _debounced() {
    final now = DateTime.now();
    if (_lastActivation != null &&
        now.difference(_lastActivation!) < _debounce) {
      return true;
    }
    _lastActivation = now;
    return false;
  }

  void _handleTap() {
    if (_debounced()) return;
    widget.onTap?.call();
  }

  void _handleLongPress() {
    if (_debounced()) return;
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap == null ? null : _handleTap,
      onLongPress: widget.onLongPress == null ? null : _handleLongPress,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
