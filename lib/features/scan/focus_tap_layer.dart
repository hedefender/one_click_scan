import 'dart:async';

import 'package:flutter/material.dart';

import '../../presentation/theme/app_colors.dart';

import 'scan_keys.dart';

/// Tap-to-focus over the preview (ADR-030). A tap reports the point as
/// fractions (0..1) of the child, which is the preview itself, and shows a
/// focus ring there that disappears by itself ([ringTime]). The ring is a
/// static drawing: there is no running animation (known limit of Phase 2).
class FocusTapLayer extends StatefulWidget {
  const FocusTapLayer({
    super.key,
    required this.child,
    required this.onFocus,
    this.ringTime = const Duration(milliseconds: 1500),
  });

  final Widget child;
  final void Function(Offset point) onFocus;
  final Duration ringTime;

  @override
  State<FocusTapLayer> createState() => _FocusTapLayerState();
}

class _FocusTapLayerState extends State<FocusTapLayer> {
  static const _ringSize = 72.0;

  Offset? _ring;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tap(TapUpDetails details) {
    // The size of the layer itself, which is the size of the preview.
    final size = context.size;
    if (size == null || size.isEmpty) return;
    final local = details.localPosition;
    widget.onFocus(
      Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      ),
    );
    _timer?.cancel();
    setState(() => _ring = local);
    _timer = Timer(widget.ringTime, () {
      if (mounted) setState(() => _ring = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ring = _ring;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _tap,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (ring != null)
            Positioned(
              left: ring.dx - _ringSize / 2,
              top: ring.dy - _ringSize / 2,
              child: IgnorePointer(
                child: Container(
                  key: ScanKeys.focusRing,
                  width: _ringSize,
                  height: _ringSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppCameraColors.content,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
