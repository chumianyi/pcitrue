import 'package:flutter_test/flutter_test.dart';
import 'package:pcitrue/paint_engine.dart';

void main() {
  test('engine starts with a single layer', () {
    final engine = PaintEngine();
    expect(engine.layers.length, 1);
    expect(engine.canUndo, false);
    engine.setBrush(BrushType.pen);
    expect(engine.brush, BrushType.pen);
  });
}
