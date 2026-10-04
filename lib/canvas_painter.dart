import 'package:flutter/material.dart';

import 'paint_engine.dart';

/// Renders the transformed canvas: checker backdrop, all layer bitmaps and
/// the in-progress stroke preview.
class CanvasPainter extends CustomPainter {
  CanvasPainter({required this.engine}) : super(repaint: engine);

  final PaintEngine engine;

  @override
  void paint(Canvas canvas, Size size) {
    // Backdrop outside the canvas.
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF222222));

    canvas.save();
    canvas.translate(engine.offset.dx, engine.offset.dy);
    canvas.scale(engine.scale);

    // White paper.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, engine.canvasSize.width, engine.canvasSize.height),
      Paint()..color = Colors.white,
    );

    // Layers bottom -> top.
    for (var i = 0; i < engine.layers.length; i++) {
      final layer = engine.layers[i];
      if (!layer.visible) continue;
      final bmp = layer.bitmap;
      if (bmp == null) continue;

      if (i == engine.activeLayerIndex && engine.stroking) {
        // Active layer: draw committed bitmap, then live stroke (which may
        // erase within an isolated buffer).
        canvas.saveLayer(
          Rect.fromLTWH(0, 0, engine.canvasSize.width, engine.canvasSize.height),
          Paint()..color = Colors.white.withOpacity(layer.opacity),
        );
        canvas.drawImage(bmp, Offset.zero, Paint());
        engine.paintLiveStroke(canvas);
        canvas.restore();
      } else {
        canvas.drawImage(
          bmp,
          Offset.zero,
          Paint()..color = Colors.white.withOpacity(layer.opacity),
        );
      }
    }

    // Paper border.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, engine.canvasSize.width, engine.canvasSize.height),
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / engine.scale,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) => true;
}
