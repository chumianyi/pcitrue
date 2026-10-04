import 'package:flutter/material.dart';

import 'paint_engine.dart';

/// Renders the transformed canvas: backdrop, replay image (if any), layers,
/// live stroke/shape preview and text items.
class CanvasPainter extends CustomPainter {
  CanvasPainter({required this.engine}) : super(repaint: engine);

  final PaintEngine engine;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF222222),
    );

    canvas.save();
    canvas.translate(engine.offset.dx, engine.offset.dy);
    canvas.scale(engine.scale);

    // White paper.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, engine.canvasSize.width, engine.canvasSize.height),
      Paint()..color = Colors.white,
    );

    if (engine.replayMode && engine.replayImage != null) {
      // Timeline replay: show the reconstructed frame only.
      canvas.drawImage(engine.replayImage!, Offset.zero, Paint());
    } else {
      // Layers bottom -> top.
      for (var i = 0; i < engine.layers.length; i++) {
        final layer = engine.layers[i];
        if (!layer.visible) continue;
        final bmp = layer.bitmap;
        if (bmp == null) continue;

        if (i == engine.activeLayerIndex && engine.stroking) {
          canvas.saveLayer(
            Rect.fromLTWH(
                0, 0, engine.canvasSize.width, engine.canvasSize.height),
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

      // Live vector shape preview.
      engine.paintLiveShape(canvas);

      // Text items.
      for (final t in engine.textItems) {
        engine.renderTextItem(canvas, t);
        if (t == engine.selectedText) {
          final rect = t.bounds();
          canvas.drawRect(
            rect,
            Paint()
              ..color = Colors.blue.withOpacity(0.6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 / engine.scale,
          );
        }
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
