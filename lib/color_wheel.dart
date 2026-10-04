import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A circular HSV color wheel picker with a brightness slider.
class ColorWheelPicker extends StatefulWidget {
  const ColorWheelPicker({super.key, required this.initialColor, this.onChanged});
  final Color initialColor;
  final ValueChanged<Color>? onChanged;

  @override
  State<ColorWheelPicker> createState() => _ColorWheelPickerState();
}

class _ColorWheelPickerState extends State<ColorWheelPicker> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  void _emit() {
    widget.onChanged?.call(_hsv.toColor());
  }

  void _handleWheelDrag(Offset local, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final d = local - center;
    final dist = d.distance.clamp(0.0, r);
    final angle = (math.atan2(d.dy, d.dx) * 180 / math.pi + 360) % 360;
    setState(() {
      _hsv = _hsv.withHue(angle).withSaturation(dist / r);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: (e) => _handleWheelDrag(e.localPosition, const Size(280, 280)),
          onPanUpdate: (e) => _handleWheelDrag(e.localPosition, const Size(280, 280)),
          child: SizedBox(
            width: 280,
            height: 280,
            child: CustomPaint(painter: _WheelPainter(_hsv)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.brightness_6, size: 20),
            Expanded(
              child: Slider(
                value: _hsv.value,
                onChanged: (v) {
                  setState(() => _hsv = _hsv.withValue(v));
                  _emit();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: 60,
          height: 30,
          decoration: BoxDecoration(
            color: _hsv.toColor(),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;

    // Outer hue ring + inner saturation disc drawn via a sweep gradient with
    // transparent center is approximated by two concentric layers.
    const bands = 360;
    const bandAngle = 2 * math.pi / bands;
    for (int i = 0; i < bands; i++) {
      final hue = i.toDouble();
      final c = HSVColor.fromAHSV(1, hue, 1, hsv.value).toColor();
      final rect = Rect.fromCircle(center: center, radius: r);
      final paint = Paint()..color = c;
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * bandAngle,
        bandAngle + 0.002,
        true,
        paint,
      );
    }

    // Mask center to white (desaturation overlay).
    final maskPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withOpacity(0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, maskPaint);

    // Selection indicator.
    final angle = hsv.hue * math.pi / 180;
    final selDist = hsv.saturation * r;
    final selPos = center + Offset(math.cos(angle), math.sin(angle)) * selDist;
    canvas.drawCircle(
      selPos,
      12,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      selPos,
      12,
      Paint()
        ..color = hsv.toColor()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}
