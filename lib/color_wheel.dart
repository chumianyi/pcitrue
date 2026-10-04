import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A circular HSV color wheel picker with a brightness slider.
///
/// Hue 0 sits at the top and increases clockwise. Drag position and the
/// selection marker are mapped to/from HSV using the standard conversion,
/// and the brightness slider is kept in sync.
class ColorWheelPicker extends StatefulWidget {
  const ColorWheelPicker({
    super.key,
    required this.initialColor,
    required this.onChanged,
  });

  final Color initialColor;
  final ValueChanged<Color> onChanged;

  @override
  State<ColorWheelPicker> createState() => _ColorWheelPickerState();
}

class _ColorWheelPickerState extends State<ColorWheelPicker> {
  static const double _size = 280.0;
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  void _emit() => widget.onChanged(_hsv.toColor());

  void _handleWheelDrag(Offset local) {
    final center = _size / 2;
    final r = _size / 2;
    final d = local - Offset(center, center);
    final dist = d.distance.clamp(0.0, r);
    // Standard atan2 gives angle from +X axis, clockwise positive (y down).
    // Hue 0 is at the top, so add 90 degrees.
    final rawDeg = math.atan2(d.dy, d.dx) * 180 / math.pi;
    final hue = (rawDeg + 90 + 360) % 360;
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
          onTapDown: (e) => _handleWheelDrag(e.localPosition),
          onPanStart: (e) => _handleWheelDrag(e.localPosition),
          onPanUpdate: (e) => _handleWheelDrag(e.localPosition),
          child: SizedBox(
            width: _size,
            height: _size,
            child: CustomPaint(painter: _WheelPainter(_hsv)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.light_mode, size: 20),
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
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Hue ring: 360 thin arcs, hue 0 at top, clockwise.
    const bands = 360;
    const bandAngle = 2 * math.pi / bands;
    for (int i = 0; i < bands; i++) {
      final c = HSVColor.fromAHSV(1, i.toDouble(), 1, hsv.value).toColor();
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        -math.pi / 2 + i * bandAngle,
        bandAngle + 0.002,
        true,
        Paint()..color = c,
      );
    }

    // Saturation mask: center is fully desaturated (the gray at current value),
    // fading to fully saturated at the rim.
    final centerGray = HSVColor.fromAHSV(1, hsv.hue, 0, hsv.value).toColor();
    final maskPaint = Paint()
      ..shader = RadialGradient(
        colors: [centerGray, centerGray.withOpacity(0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, maskPaint);

    // Selection marker: hue measured clockwise from the top.
    final a = (hsv.hue - 90) * math.pi / 180;
    final selDist = hsv.saturation * r;
    final selPos = center + Offset(math.cos(a), math.sin(a)) * selDist;
    canvas.drawCircle(selPos, 11, Paint()..color = Colors.white);
    canvas.drawCircle(
      selPos,
      11,
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
