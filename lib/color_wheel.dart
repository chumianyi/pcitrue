import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A circular HSV color wheel picker with accurate HSV↔RGB conversion.
/// Hue comes from the angle, saturation from the distance from center,
/// brightness from the slider below.
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
    // Angle: 0° = right (east), counterclockwise positive in atan2,
    // but HSV hue starts at red=0° going clockwise.
    var angle = math.atan2(d.dy, d.dx) * 180 / math.pi;
    angle = (angle + 360) % 360;
    // Flutter's HSVColor uses hue 0-360 where 0=red, going clockwise.
    // atan2 gives 0=east(red), 90=south. In Flutter color wheel,
    // we want red at top (like a standard color wheel).
    final hue = (angle + 90) % 360;
    setState(() {
      _hsv = _hsv.withHue(hue).withSaturation(dist / r);
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
                min: 0,
                max: 1,
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 30,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '#${(_hsv.toColor().value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
          ],
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

    // Draw the wheel as concentric rings with proper hue+saturation.
    // For each angular sector, draw a filled arc from inner (white, S=0)
    // to outer (pure hue, S=1). We approximate with thin ring segments.
    const segments = 72; // 5° each
    const rings = 20;

    for (int ring = 1; ring <= rings; ring++) {
      final s = ring / rings; // saturation 0..1
      final innerR = r * (ring - 1) / rings;
      final outerR = r * ring / rings;
      for (int i = 0; i < segments; i++) {
        final hue = i * (360 / segments);
        final c = HSVColor.fromAHSV(1, hue.toDouble(), s, hsv.value).toColor();
        final rect = Rect.fromCircle(center: center, radius: outerR);
        // Start angle: -90° (top = red), going clockwise
        final startAngle = -math.pi / 2 + (i * 2 * math.pi / segments);
        final sweepAngle = 2 * math.pi / segments + 0.01;
        canvas.drawArc(
          rect,
          startAngle,
          sweepAngle,
          true,
          Paint()..color = c,
        );
        // Cover inner hole of this ring segment
        if (innerR > 0) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: innerR),
            startAngle,
            sweepAngle,
            true,
            Paint()..color = Colors.white, // will be overwritten by inner ring
          );
        }
      }
    }

    // Selection indicator
    final angle = (hsv.hue - 90) * math.pi / 180; // convert back
    final selDist = hsv.saturation * r;
    final selPos = center + Offset(math.cos(angle), math.sin(angle)) * selDist;
    canvas.drawCircle(selPos, 12, Paint()..color = Colors.white);
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
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => oldDelegate.hsv != hsv;
}
