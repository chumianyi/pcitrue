import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Supported brush types (18 distinct textures).
enum BrushType {
  pen,
  pencil,
  pencilSoft,
  pencilHard,
  marker,
  markerThin,
  calligraphy,
  crayon,
  chalk,
  charcoal,
  watercolor,
  oil,
  neon,
  nebula,
  starlight,
  airbrush,
  blur,
  eraser,
}

extension BrushTypeX on BrushType {
  String get label {
    switch (this) {
      case BrushType.pen:
        return '钢笔';
      case BrushType.pencil:
        return '铅笔';
      case BrushType.pencilSoft:
        return '软铅笔';
      case BrushType.pencilHard:
        return '硬铅笔';
      case BrushType.marker:
        return '马克笔';
      case BrushType.markerThin:
        return '细马克笔';
      case BrushType.calligraphy:
        return '毛笔';
      case BrushType.crayon:
        return '蜡笔';
      case BrushType.chalk:
        return '粉笔';
      case BrushType.charcoal:
        return '炭笔';
      case BrushType.watercolor:
        return '水彩';
      case BrushType.oil:
        return '油画';
      case BrushType.neon:
        return '发光';
      case BrushType.nebula:
        return '星云';
      case BrushType.starlight:
        return '星光';
      case BrushType.airbrush:
        return '喷雾';
      case BrushType.blur:
        return '模糊笔';
      case BrushType.eraser:
        return '橡皮';
    }
  }

  IconData get icon {
    switch (this) {
      case BrushType.pen:
        return Icons.edit;
      case BrushType.pencil:
        return Icons.create;
      case BrushType.pencilSoft:
        return Icons.edit_outlined;
      case BrushType.pencilHard:
        return Icons.draw_outlined;
      case BrushType.marker:
        return Icons.brush;
      case BrushType.markerThin:
        return Icons.brush_outlined;
      case BrushType.calligraphy:
        return Icons.font_download;
      case BrushType.crayon:
        return Icons.colorize;
      case BrushType.chalk:
        return Icons.grain;
      case BrushType.charcoal:
        return Icons.blur_on;
      case BrushType.watercolor:
        return Icons.water_drop;
      case BrushType.oil:
        return Icons.palette;
      case BrushType.neon:
        return Icons.lightbulb;
      case BrushType.nebula:
        return Icons.cloud;
      case BrushType.starlight:
        return Icons.star;
      case BrushType.airbrush:
        return Icons.spa;
      case BrushType.blur:
        return Icons.blur_circular;
      case BrushType.eraser:
        return Icons.auto_fix_off;
    }
  }
}

/// Drawing tools: freehand, vector shapes, text.
enum Tool { draw, line, rect, ellipse, text }

/// A single painting layer holding a committed offscreen bitmap.
class PainterLayer {
  PainterLayer({required this.name, this.bitmap, this.opacity = 1.0, this.visible = true});

  String name;
  ui.Image? bitmap;
  double opacity;
  bool visible;
}

/// A movable text object stamped on the canvas.
class TextItem {
  TextItem({required this.text, required this.pos, required this.size, required this.color});

  String text;
  Offset pos;
  double size;
  Color color;

  TextItem clone() => TextItem(text: text, pos: pos, size: size, color: color);

  Rect bounds() {
    final w = text.length * size * 0.62;
    final h = size * 1.25;
    return Rect.fromCenter(center: pos, width: w, height: h);
  }
}

class _UndoEntry {
  _UndoEntry({required this.layerIndex, required this.oldBitmap, required this.newBitmap});
  final int layerIndex;
  final ui.Image? oldBitmap;
  final ui.Image? newBitmap;
}

class _BrushCfg {
  _BrushCfg({required this.type, required this.color, required this.size});
  final BrushType type;
  final Color color;
  final double size;
}

/// One recorded painting action, used for timeline replay.
class PaintingStep {
  PaintingStep.free({
    required this.layerIndex,
    required this.type,
    required this.color,
    required this.size,
    required this.points,
  })  : shape = 'free',
        shapeRect = null,
        text = null,
        imagePng = null;

  PaintingStep.shape({
    required this.layerIndex,
    required this.type,
    required this.color,
    required this.size,
    required this.shape,
    required this.shapeRect,
  })  : points = const [],
        text = null,
        imagePng = null;

  PaintingStep.text(this.text)
      : layerIndex = -1,
        type = BrushType.pen,
        color = const Color(0xFF000000),
        size = 16,
        shape = 'text',
        points = const [],
        shapeRect = null,
        imagePng = null;

  PaintingStep.imageLayer(this.imagePng)
      : layerIndex = -1,
        type = BrushType.pen,
        color = const Color(0xFF000000),
        size = 16,
        shape = 'image',
        points = const [],
        shapeRect = null,
        text = null;

  final int layerIndex;
  final BrushType type;
  final Color color;
  final double size;
  final List<Offset> points;
  final String shape;
  final Rect? shapeRect;
  final TextItem? text;
  final Uint8List? imagePng;
}

enum _GestureMode { none, draw, transform, shape, textDrag }

class PaintEngine extends ChangeNotifier {
  PaintEngine() {
    layers.add(PainterLayer(name: '图层 1'));
  }

  final Size canvasSize = const Size(1080, 1920);

  final List<PainterLayer> layers = [];
  int activeLayerIndex = 0;
  bool layersEnabled = true;
  String glVersion = 'unknown';

  Tool tool = Tool.draw;
  BrushType brush = BrushType.pen;
  Color color = const Color(0xFF1A73E8);
  double brushSize = 14.0;
  bool shapeFilled = false;

  // ---- Text ----
  final List<TextItem> textItems = [];
  TextItem? selectedText;

  /// Called when the user taps empty canvas while in text tool mode; the UI
  /// shows a dialog and then calls [addTextItem].
  void Function(Offset canvasPoint)? onTextTap;

  // ---- Transform ----
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double get scale => _scale;
  Offset get offset => _offset;

  // ---- In-progress stroke ----
  final List<Offset> _stroke = [];
  bool _stroking = false;
  bool get stroking => _stroking;

  // ---- In-progress shape ----
  Offset? _shapeStart;
  Offset? _shapeCurrent;
  Offset? get shapeStart => _shapeStart;
  Offset? get shapeCurrent => _shapeCurrent;

  Offset? _textDragStart;
  Offset? _textDownStart;

  _GestureMode _mode = _GestureMode.none;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;

  // ---- Undo / redo ----
  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];
  static const int _maxUndo = 30;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  // ---- Steps / timeline ----
  final List<PaintingStep> steps = [];
  static const int _maxSteps = 300;
  bool _replayMode = false;
  bool get replayMode => _replayMode;
  ui.Image? _replayImage;
  ui.Image? get replayImage => _replayImage;

  bool _committing = false;

  PainterLayer get activeLayer => layers[activeLayerIndex];

  Offset screenToCanvas(Offset screen) => (screen - _offset) / _scale;

  void _clampTransform() => _scale = _scale.clamp(0.1, 6.0);

  // ---------------------------------------------------------------------
  void onScaleStart(ScaleStartDetails details, Size viewport) {
    if (details.pointerCount >= 2) {
      _mode = _GestureMode.transform;
      if (_stroking) _commitStroke();
      _shapeStart = null;
      _shapeCurrent = null;
      _baseScale = _scale;
      _baseOffset = _offset;
      return;
    }

    final p = screenToCanvas(details.localFocalPoint);

    if (tool == Tool.text) {
      final hit = hitTestText(p);
      if (hit != null) {
        _mode = _GestureMode.textDrag;
        selectedText = hit;
        _textDragStart = p;
        notifyListeners();
      } else {
        _mode = _GestureMode.none;
        _textDownStart = p;
      }
      return;
    }

    if (tool == Tool.line || tool == Tool.rect || tool == Tool.ellipse) {
      _mode = _GestureMode.shape;
      _shapeStart = p;
      _shapeCurrent = p;
      notifyListeners();
      return;
    }

    _mode = _GestureMode.draw;
    _stroke.clear();
    _stroke.add(p);
    _stroking = true;
    notifyListeners();
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    if (_mode == _GestureMode.transform || details.pointerCount >= 2) {
      if (_stroking) _commitStroke();
      _mode = _GestureMode.transform;
      final newScale = _baseScale * details.scale;
      final f = details.localFocalPoint;
      _offset = f - (f - _baseOffset) * (newScale / _baseScale);
      _scale = newScale;
      _clampTransform();
      notifyListeners();
      return;
    }

    final p = screenToCanvas(details.localFocalPoint);

    if (_mode == _GestureMode.textDrag && selectedText != null) {
      selectedText!.pos += p - _textDragStart!;
      _textDragStart = p;
      notifyListeners();
      return;
    }

    if (_mode == _GestureMode.shape) {
      _shapeCurrent = p;
      notifyListeners();
      return;
    }

    if (_mode == _GestureMode.draw && _stroking) {
      if (_stroke.isEmpty || (p - _stroke.last).distance > 0.5) {
        _stroke.add(p);
        notifyListeners();
      }
    }
  }

  void onScaleEnd(ScaleEndDetails details) {
    if (_mode == _GestureMode.draw && _stroking) {
      _commitStroke();
    } else if (_mode == _GestureMode.shape) {
      _commitShape();
    } else if (_mode == _GestureMode.textDrag) {
      scheduleMicrotask(() => onProjectChanged?.call());
    } else if (_mode == _GestureMode.none && tool == Tool.text && _textDownStart != null) {
      final p = _textDownStart!;
      _textDownStart = null;
      onTextTap?.call(p);
    }
    _mode = _GestureMode.none;
  }

  /// Add a text object (from the UI dialog).
  void addTextItem(TextItem item) {
    textItems.add(item);
    selectedText = item;
    steps.add(PaintingStep.text(item.clone()));
    if (steps.length > _maxSteps) steps.removeAt(0);
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  // ---------------------------------------------------------------------
  Future<void> _commitStroke() async {
    if (_committing) return;
    _committing = true;

    final pts = List<Offset>.from(_stroke);
    _stroke.clear();
    _stroking = false;

    if (pts.isEmpty) {
      _committing = false;
      notifyListeners();
      return;
    }

    final layer = activeLayer;
    final oldBitmap = layer.bitmap;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (oldBitmap != null) canvas.drawImage(oldBitmap, Offset.zero, Paint());

    final cfg = _BrushCfg(type: brush, color: color, size: brushSize);
    _renderStroke(canvas, pts, cfg);

    final picture = recorder.endRecording();
    final ui.Image img = await picture.toImage(canvasSize.width.round(), canvasSize.height.round());

    layer.bitmap = img;
    _pushUndo(_UndoEntry(layerIndex: activeLayerIndex, oldBitmap: oldBitmap, newBitmap: img));
    _redoStack.clear();

    steps.add(PaintingStep.free(
      layerIndex: activeLayerIndex,
      type: brush,
      color: color,
      size: brushSize,
      points: pts,
    ));
    if (steps.length > _maxSteps) steps.removeAt(0);

    _committing = false;
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  Future<void> _commitShape() async {
    final a = _shapeStart;
    final b = _shapeCurrent;
    _shapeStart = null;
    _shapeCurrent = null;
    if (a == null || b == null || (a - b).distance < 4) {
      notifyListeners();
      return;
    }
    final layer = activeLayer;
    final oldBitmap = layer.bitmap;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (oldBitmap != null) canvas.drawImage(oldBitmap, Offset.zero, Paint());

    final rect = Rect.fromPoints(a, b);
    final paint = Paint()
      ..color = color
      ..strokeWidth = brushSize
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..style = shapeFilled ? PaintingStyle.fill : PaintingStyle.stroke;

    String shapeName;
    switch (tool) {
      case Tool.line:
        canvas.drawLine(a, b, paint);
        shapeName = 'line';
        break;
      case Tool.rect:
        canvas.drawRect(rect, paint);
        shapeName = 'rect';
        break;
      case Tool.ellipse:
        canvas.drawOval(rect, paint);
        shapeName = 'circle';
        break;
      default:
        shapeName = 'line';
    }

    final picture = recorder.endRecording();
    final ui.Image img = await picture.toImage(canvasSize.width.round(), canvasSize.height.round());
    layer.bitmap = img;
    _pushUndo(_UndoEntry(layerIndex: activeLayerIndex, oldBitmap: oldBitmap, newBitmap: img));
    _redoStack.clear();

    steps.add(PaintingStep.shape(
      layerIndex: activeLayerIndex,
      type: BrushType.pen,
      color: color,
      size: brushSize,
      shape: shapeName,
      shapeRect: rect,
    ));
    if (steps.length > _maxSteps) steps.removeAt(0);

    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  void _pushUndo(_UndoEntry e) {
    _undoStack.add(e);
    if (_undoStack.length > _maxUndo) {
      final removed = _undoStack.removeAt(0);
      removed.oldBitmap?.dispose();
      removed.newBitmap?.dispose();
    }
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final e = _undoStack.removeLast();
    layers[e.layerIndex].bitmap = e.oldBitmap;
    _redoStack.add(e);
    if (steps.isNotEmpty) steps.removeLast();
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final e = _redoStack.removeLast();
    layers[e.layerIndex].bitmap = e.newBitmap;
    _undoStack.add(e);
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  // ---------------------------------------------------------------------
  void _renderStroke(Canvas canvas, List<Offset> pts, _BrushCfg cfg) {
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _stampDab(canvas, pts.first, cfg, 0, 0, 0);
      return;
    }
    int seed = 1;
    for (int i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final dist = (b - a).distance;
      final step = (cfg.size * 0.18).clamp(0.8, 14.0);
      final n = (dist / step).ceil();
      for (int j = 0; j <= n; j++) {
        final t = n == 0 ? 0.0 : j / n;
        final p = Offset.lerp(a, b, t)!;
        _stampDab(canvas, p, cfg, seed++, j, dist);
      }
    }
  }

  void _stampDab(Canvas canvas, Offset p, _BrushCfg cfg, int seed, int sub, double speed) {
    final rng = math.Random(seed * 131 + sub * 17);
    final r = cfg.size / 2;
    switch (cfg.type) {
      case BrushType.pen:
        // Crisp opaque nib, no tail.
        canvas.drawCircle(p, r, Paint()..color = cfg.color..isAntiAlias = true);
        break;
      case BrushType.pencil:
        for (int k = 0; k < 2; k++) {
          final jx = (rng.nextDouble() - 0.5) * r * 1.6;
          final jy = (rng.nextDouble() - 0.5) * r * 1.6;
          canvas.drawCircle(p + Offset(jx, jy), r * 0.35,
              Paint()..color = cfg.color.withOpacity(0.45));
        }
        break;
      case BrushType.pencilSoft:
        for (int k = 0; k < 3; k++) {
          final jx = (rng.nextDouble() - 0.5) * r * 2.2;
          final jy = (rng.nextDouble() - 0.5) * r * 2.2;
          canvas.drawCircle(p + Offset(jx, jy), r * 0.3,
              Paint()..color = cfg.color.withOpacity(0.28));
        }
        break;
      case BrushType.pencilHard:
        canvas.drawCircle(p, r * 0.32, Paint()..color = cfg.color.withOpacity(0.7));
        break;
      case BrushType.marker:
        canvas.drawCircle(p, r, Paint()..color = cfg.color.withOpacity(0.28));
        break;
      case BrushType.markerThin:
        canvas.drawCircle(p, r * 0.55, Paint()..color = cfg.color.withOpacity(0.4));
        break;
      case BrushType.calligraphy:
        final w = (r * (1.6 - (speed / 60).clamp(0.4, 1.2))).clamp(r * 0.4, r * 1.6);
        canvas.drawCircle(p, w, Paint()..color = cfg.color.withOpacity(0.9)..isAntiAlias = true);
        break;
      case BrushType.crayon:
        canvas.drawCircle(p, r, Paint()..color = cfg.color.withOpacity(0.85));
        for (int k = 0; k < 3; k++) {
          final jx = (rng.nextDouble() - 0.5) * r * 0.6;
          final jy = (rng.nextDouble() - 0.5) * r * 0.6;
          canvas.drawCircle(p + Offset(jx, jy), r * 0.18,
              Paint()..color = cfg.color.withOpacity(0.3));
        }
        break;
      case BrushType.chalk:
        for (int k = 0; k < 4; k++) {
          final jx = (rng.nextDouble() - 0.5) * r * 1.4;
          final jy = (rng.nextDouble() - 0.5) * r * 1.4;
          canvas.drawCircle(p + Offset(jx, jy), r * 0.22,
              Paint()..color = cfg.color.withOpacity(0.35));
        }
        break;
      case BrushType.charcoal:
        for (int k = 0; k < 5; k++) {
          final jx = (rng.nextDouble() - 0.5) * r * 1.8;
          final jy = (rng.nextDouble() - 0.5) * r * 1.8;
          canvas.drawCircle(p + Offset(jx, jy), r * 0.2,
              Paint()..color = cfg.color.withOpacity(0.45));
        }
        break;
      case BrushType.watercolor:
        canvas.drawCircle(p, r * 1.25, Paint()..color = cfg.color.withOpacity(0.06));
        canvas.drawCircle(
            p + Offset((rng.nextDouble() - 0.5) * r * 0.4, (rng.nextDouble() - 0.5) * r * 0.4),
            r * 0.8,
            Paint()..color = cfg.color.withOpacity(0.05));
        break;
      case BrushType.oil:
        canvas.drawCircle(p, r * 0.7, Paint()..color = cfg.color.withOpacity(0.85));
        canvas.drawCircle(
            p + Offset((rng.nextDouble() - 0.5) * r * 0.3, (rng.nextDouble() - 0.5) * r * 0.3),
            r * 0.35,
            Paint()..color = cfg.color.withOpacity(0.5));
        break;
      case BrushType.neon:
        canvas.drawCircle(p, r * 1.8, Paint()..color = cfg.color.withOpacity(0.12));
        canvas.drawCircle(p, r * 0.6, Paint()..color = cfg.color.withOpacity(0.95));
        break;
      case BrushType.nebula:
        canvas.drawCircle(p, r * 2.2, Paint()..color = cfg.color.withOpacity(0.05));
        for (int k = 0; k < 3; k++) {
          final ang = rng.nextDouble() * 2 * math.pi;
          final rad = rng.nextDouble() * r * 1.5;
          canvas.drawCircle(p + Offset(math.cos(ang), math.sin(ang)) * rad, 1.2,
              Paint()..color = Colors.white.withOpacity(0.5));
        }
        break;
      case BrushType.starlight:
        final len = r * (1.0 + rng.nextDouble() * 0.6);
        final c = Paint()..color = cfg.color.withOpacity(0.9)..strokeWidth = 1.4;
        canvas.drawLine(p - Offset(len, 0), p + Offset(len, 0), c);
        canvas.drawLine(p - Offset(0, len), p + Offset(0, len), c);
        canvas.drawCircle(p, r * 0.4, Paint()..color = Colors.white);
        break;
      case BrushType.airbrush:
        for (int k = 0; k < 7; k++) {
          final ang = rng.nextDouble() * 2 * math.pi;
          final rad = math.sqrt(rng.nextDouble()) * r;
          final dp = p + Offset(math.cos(ang), math.sin(ang)) * rad;
          canvas.drawCircle(dp, 1.0, Paint()..color = cfg.color.withOpacity(0.16));
        }
        break;
      case BrushType.blur:
        canvas.drawCircle(p, r * 1.4, Paint()..color = cfg.color.withOpacity(0.08));
        break;
      case BrushType.eraser:
        canvas.drawCircle(p, r, Paint()..blendMode = BlendMode.clear);
        break;
    }
  }

  void paintLiveStroke(Canvas canvas) {
    if (!_stroking || _stroke.isEmpty) return;
    final cfg = _BrushCfg(type: brush, color: color, size: brushSize);
    if (brush == BrushType.eraser) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
        Paint(),
      );
      final bmp = activeLayer.bitmap;
      if (bmp != null) canvas.drawImage(bmp, Offset.zero, Paint());
      _renderStroke(canvas, _stroke, cfg);
      canvas.restore();
    } else {
      _renderStroke(canvas, _stroke, cfg);
    }
  }

  void paintLiveShape(Canvas canvas) {
    final a = _shapeStart;
    final b = _shapeCurrent;
    if (a == null || b == null) return;
    final rect = Rect.fromPoints(a, b);
    final paint = Paint()
      ..color = color.withOpacity(0.9)
      ..strokeWidth = brushSize
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..style = shapeFilled ? PaintingStyle.fill : PaintingStyle.stroke;
    switch (tool) {
      case Tool.line:
        canvas.drawLine(a, b, paint);
        break;
      case Tool.rect:
        canvas.drawRect(rect, paint);
        break;
      case Tool.ellipse:
        canvas.drawOval(rect, paint);
        break;
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------
  TextItem? hitTestText(Offset p) {
    for (var i = textItems.length - 1; i >= 0; i--) {
      if (textItems[i].bounds().contains(p)) return textItems[i];
    }
    return null;
  }

  void renderTextItem(Canvas canvas, TextItem t) {
    final tp = TextPainter(
      text: TextSpan(
        text: t.text,
        style: TextStyle(color: t.color, fontSize: t.size, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, t.pos - Offset(tp.width / 2, tp.height / 2));
  }

  // ---------------------------------------------------------------------
  void addLayer() {
    if (!layersEnabled) return;
    final newIndex = activeLayerIndex + 1;
    layers.insert(newIndex, PainterLayer(name: '图层 ${layers.length + 1}'));
    activeLayerIndex = newIndex;
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  /// Add an already-decoded image as a new top layer, cover-fitted.
  Future<void> addImageAsLayer(ui.Image image) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final s = math.max(canvasSize.width / image.width, canvasSize.height / image.height);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(center: canvasSize.center(Offset.zero), width: image.width * s, height: image.height * s),
      Paint(),
    );
    final pic = recorder.endRecording();
    final img = await pic.toImage(canvasSize.width.round(), canvasSize.height.round());
    layers.add(PainterLayer(name: '叠加图片', bitmap: img));
    activeLayerIndex = layers.length - 1;
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bd != null) steps.add(PaintingStep.imageLayer(bd.buffer.asUint8List()));
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  /// Clear to blank and put the decoded image as the single bottom base layer.
  Future<void> importImageAsBase(ui.Image image) async {
    clearToBlank();
    await addImageAsLayer(image);
  }

  void deleteLayer(int i) {
    if (layers.length <= 1) return;
    layers[i].bitmap?.dispose();
    layers.removeAt(i);
    if (activeLayerIndex >= layers.length) {
      activeLayerIndex = layers.length - 1;
    } else if (activeLayerIndex > i) {
      activeLayerIndex--;
    }
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  void setActiveLayer(int i) {
    if (i < 0 || i >= layers.length) return;
    activeLayerIndex = i;
    notifyListeners();
  }

  void toggleVisibility(int i) {
    layers[i].visible = !layers[i].visible;
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  void setLayerOpacity(int i, double v) {
    layers[i].opacity = v;
    notifyListeners();
  }

  void moveLayerUp(int i) {
    if (i >= layers.length - 1) return;
    final l = layers.removeAt(i);
    layers.insert(i + 1, l);
    if (activeLayerIndex == i) activeLayerIndex = i + 1;
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  void moveLayerDown(int i) {
    if (i <= 0) return;
    final l = layers.removeAt(i);
    layers.insert(i - 1, l);
    if (activeLayerIndex == i) activeLayerIndex = i - 1;
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  // ---------------------------------------------------------------------
  void setTool(Tool t) {
    tool = t;
    selectedText = null;
    notifyListeners();
  }

  void setBrush(BrushType b) {
    brush = b;
    tool = Tool.draw;
    notifyListeners();
  }

  void setColor(Color c) {
    color = c;
    if (selectedText != null) selectedText!.color = c;
    notifyListeners();
  }

  void setBrushSize(double s) {
    brushSize = s;
    if (selectedText != null) selectedText!.size = s;
    notifyListeners();
  }

  void resetView(Size viewport) {
    final scaleX = viewport.width / canvasSize.width;
    final scaleY = viewport.height / canvasSize.height;
    _scale = math.min(scaleX, scaleY);
    _offset = Offset(
      (viewport.width - canvasSize.width * _scale) / 2,
      (viewport.height - canvasSize.height * _scale) / 2,
    );
    notifyListeners();
  }

  VoidCallback? onProjectChanged;

  /// Reset to a blank project (used after loading / clearing).
  void clearToBlank() {
    for (final l in layers) {
      l.bitmap?.dispose();
    }
    layers
      ..clear()
      ..add(PainterLayer(name: '图层 1'));
    activeLayerIndex = 0;
    textItems.clear();
    steps.clear();
    notifyListeners();
  }

  /// Replace state when loading a project.
  Future<void> replaceFromLoaded({
    required List<PainterLayer> loadedLayers,
    required int activeIndex,
    List<TextItem>? loadedText,
  }) async {
    for (final l in layers) {
      l.bitmap?.dispose();
    }
    layers
      ..clear()
      ..addAll(loadedLayers);
    activeLayerIndex = activeIndex.clamp(0, layers.length - 1);
    textItems
      ..clear()
      ..addAll(loadedText ?? []);
    steps.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Timeline replay
  // ---------------------------------------------------------------------
  Future<void> startReplay(int upTo) async {
    upTo = upTo.clamp(0, steps.length);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
      Paint()..color = Colors.white,
    );
    for (var i = 0; i <= upTo && i < steps.length; i++) {
      await _applyStepForReplay(canvas, steps[i]);
    }
    final pic = recorder.endRecording();
    final img = await pic.toImage(canvasSize.width.round(), canvasSize.height.round());
    _replayImage?.dispose();
    _replayImage = img;
    _replayMode = true;
    notifyListeners();
  }

  Future<void> _applyStepForReplay(Canvas canvas, PaintingStep s) async {
    switch (s.shape) {
      case 'free':
        _renderStroke(canvas, s.points, _BrushCfg(type: s.type, color: s.color, size: s.size));
        break;
      case 'line':
        final r = s.shapeRect!;
        canvas.drawLine(r.topLeft, r.bottomRight, Paint()
          ..color = s.color
          ..strokeWidth = s.size
          ..strokeCap = StrokeCap.round);
        break;
      case 'rect':
        canvas.drawRect(s.shapeRect!, Paint()
          ..color = s.color
          ..strokeWidth = s.size
          ..style = PaintingStyle.stroke);
        break;
      case 'circle':
        canvas.drawOval(s.shapeRect!, Paint()
          ..color = s.color
          ..strokeWidth = s.size
          ..style = PaintingStyle.stroke);
        break;
      case 'text':
        if (s.text != null) renderTextItem(canvas, s.text!);
        break;
      case 'image':
        if (s.imagePng != null) {
          final decoded = await _decode(s.imagePng!);
          canvas.drawImage(decoded, Offset.zero, Paint());
        }
        break;
    }
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void stopReplay() {
    _replayMode = false;
    _replayImage?.dispose();
    _replayImage = null;
    notifyListeners();
  }
}
