import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui';

import 'package:flutter/material.dart';

// =============================================================================
// Brush Types — 15+ brushes
// =============================================================================
enum BrushType {
  pen,
  pencilHard,
  pencilSoft,
  marker,
  markerThin,
  markerThick,
  crayon,
  watercolor,
  oil,
  chalk,
  charcoal,
  glow,
  nebula,
  starlight,
  calligraphy,
  airbrush,
  blur,
  eraser,
}

extension BrushTypeX on BrushType {
  String get label {
    switch (this) {
      case BrushType.pen: return '钢笔';
      case BrushType.pencilHard: return '硬铅笔';
      case BrushType.pencilSoft: return '软铅笔';
      case BrushType.marker: return '马克笔';
      case BrushType.markerThin: return '细马克笔';
      case BrushType.markerThick: return '粗马克笔';
      case BrushType.crayon: return '蜡笔';
      case BrushType.watercolor: return '水彩';
      case BrushType.oil: return '油画';
      case BrushType.chalk: return '粉笔';
      case BrushType.charcoal: return '炭笔';
      case BrushType.glow: return '发光';
      case BrushType.nebula: return '星云';
      case BrushType.starlight: return '星光';
      case BrushType.calligraphy: return '毛笔';
      case BrushType.airbrush: return '喷雾';
      case BrushType.blur: return '模糊';
      case BrushType.eraser: return '橡皮';
    }
  }

  IconData get icon {
    switch (this) {
      case BrushType.pen: return Icons.edit;
      case BrushType.pencilHard: return Icons.create;
      case BrushType.pencilSoft: return Icons.draw_outlined;
      case BrushType.marker: return Icons.brush;
      case BrushType.markerThin: return Icons.brush_outlined;
      case BrushType.markerThick: return Icons.colorize;
      case BrushType.crayon: return Icons.draw;
      case BrushType.watercolor: return Icons.water_drop;
      case BrushType.oil: return Icons.palette;
      case BrushType.chalk: return Icons.bakery_dining;
      case BrushType.charcoal: return Icons.ink_pen;
      case BrushType.glow: return Icons.auto_awesome;
      case BrushType.nebula: return Icons.nightlight;
      case BrushType.starlight: return Icons.star;
      case BrushType.calligraphy: return Icons.font_download;
      case BrushType.airbrush: return Icons.spa;
      case BrushType.blur: return Icons.blur_on;
      case BrushType.eraser: return Icons.auto_fix_off;
    }
  }
}

// =============================================================================
// Tool modes
// =============================================================================
enum ToolMode { draw, line, rect, circle, ellipse, text, imageMove }

extension ToolModeX on ToolMode {
  IconData get icon {
    switch (this) {
      case ToolMode.draw: return Icons.brush;
      case ToolMode.line: return Icons.show_chart;
      case ToolMode.rect: return Icons.crop_square;
      case ToolMode.circle: return Icons.radio_button_unchecked;
      case ToolMode.ellipse: return Icons.circle_outlined;
      case ToolMode.text: return Icons.text_fields;
      case ToolMode.imageMove: return Icons.picture_in_picture;
    }
  }
}

// =============================================================================
// Layer
// =============================================================================
class PainterLayer {
  PainterLayer({
    required this.name,
    this.bitmap,
    this.opacity = 1.0,
    this.visible = true,
  });

  String name;
  ui.Image? bitmap;
  double opacity;
  bool visible;

  PainterLayer clone() => PainterLayer(
        name: name,
        bitmap: bitmap,
        opacity: opacity,
        visible: visible,
      );
}

// =============================================================================
// Undo / Step entries
// =============================================================================
class UndoEntry {
  UndoEntry({
    required this.layerIndex,
    required this.oldBitmap,
    required this.newBitmap,
  });
  final int layerIndex;
  final ui.Image? oldBitmap;
  final ui.Image? newBitmap;
}

/// A recorded step for timeline playback.
class CanvasStep {
  CanvasStep({
    required this.layerIndex,
    required this.brushType,
    required this.color,
    required this.size,
    required this.points,
    required this.toolMode,
    this.textContent,
    this.textPos,
    this.textSize,
  });
  final int layerIndex;
  final BrushType brushType;
  final Color color;
  final double size;
  final List<Offset> points;
  final ToolMode toolMode;
  final String? textContent;
  final Offset? textPos;
  final double? textSize;
}

class _BrushCfg {
  _BrushCfg({required this.type, required this.color, required this.size});
  final BrushType type;
  final Color color;
  final double size;
}

enum _GestureMode { none, draw, transform, shape, textPlacement }

// =============================================================================
// Painting Engine
// =============================================================================
class PaintEngine extends ChangeNotifier {
  PaintEngine() {
    layers.add(PainterLayer(name: '图层 1'));
  }

  // ---- Canvas ----
  final Size canvasSize = const Size(1080, 1920);

  // ---- Layers ----
  final List<PainterLayer> layers = [];
  int activeLayerIndex = 0;
  bool layersEnabled = true;
  String glVersion = 'unknown';

  // ---- Current brush & tool ----
  BrushType brush = BrushType.crayon;
  ToolMode tool = ToolMode.draw;
  Color color = const Color(0xFF1A73E8);
  double brushSize = 14.0;

  // ---- Transform ----
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double get scale => _scale;
  Offset get offset => _offset;

  // ---- In-progress stroke ----
  final List<Offset> _stroke = [];
  bool _stroking = false;
  bool get stroking => _stroking;
  List<Offset> get strokePoints => List.unmodifiable(_stroke);

  // ---- Shape drawing start point ----
  Offset? _shapeStart;

  // ---- Text pending placement ----
  String? _pendingText;
  double _pendingTextSize = 32;
  String? get pendingText => _pendingText;
  void setPendingText(String? t, {double? size}) {
    _pendingText = t;
    if (size != null) _pendingTextSize = size;
    notifyListeners();
  }

  // ---- Gesture bookkeeping ----
  _GestureMode _mode = _GestureMode.none;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;

  // ---- Undo / redo ----
  final List<UndoEntry> _undoStack = [];
  final List<UndoEntry> _redoStack = [];
  static const int _maxUndo = 50;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  // ---- Step history for playback ----
  final List<CanvasStep> steps = [];
  bool get hasSteps => steps.isNotEmpty;

  bool _committing = false;

  PainterLayer get activeLayer => layers[activeLayerIndex];

  // ---------------------------------------------------------------------------
  // Coordinate conversion
  // ---------------------------------------------------------------------------
  Offset screenToCanvas(Offset screen) => (screen - _offset) / _scale;

  void _clampTransform() {
    _scale = _scale.clamp(0.1, 6.0);
  }

  // ---------------------------------------------------------------------------
  // Gesture handlers
  // ---------------------------------------------------------------------------
  void onScaleStart(ScaleStartDetails details, Size viewport) {
    if (details.pointerCount >= 2) {
      _mode = _GestureMode.transform;
      if (_stroking) _commitStroke();
      _baseScale = _scale;
      _baseOffset = _offset;
      return;
    }

    final p = screenToCanvas(details.localFocalPoint);

    // Text placement mode
    if (tool == ToolMode.text && _pendingText != null) {
      _commitText(_pendingText!, p, _pendingTextSize);
      _pendingText = null;
      notifyListeners();
      return;
    }

    // Shape tools
    if (tool == ToolMode.line ||
        tool == ToolMode.rect ||
        tool == ToolMode.circle ||
        tool == ToolMode.ellipse) {
      _mode = _GestureMode.shape;
      _shapeStart = p;
      _stroke.clear();
      _stroke.add(p);
      _stroking = true;
      notifyListeners();
      return;
    }

    // Normal drawing
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
      final newScale = (_baseScale * details.scale);
      final f = details.localFocalPoint;
      _offset = f - (f - _baseOffset) * (newScale / _baseScale);
      _scale = newScale;
      _clampTransform();
      notifyListeners();
      return;
    }

    if (_stroking) {
      final p = screenToCanvas(details.localFocalPoint);
      if (_stroke.isEmpty || (p - _stroke.last).distance > 0.5) {
        _stroke.add(p);
        notifyListeners();
      }
    }
  }

  void onScaleEnd(ScaleEndDetails details) {
    if (_stroking) _commitStroke();
    _mode = _GestureMode.none;
    _shapeStart = null;
  }

  // ---------------------------------------------------------------------------
  // Stroke baking
  // ---------------------------------------------------------------------------
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
    if (oldBitmap != null) {
      canvas.drawImage(oldBitmap, Offset.zero, Paint());
    }

    final cfg = _BrushCfg(type: brush, color: color, size: brushSize);

    if (_mode == _GestureMode.shape && _shapeStart != null) {
      _renderShape(canvas, _shapeStart!, pts.last, tool, cfg);
    } else {
      _renderStroke(canvas, pts, cfg);
    }

    final picture = recorder.endRecording();
    final ui.Image img = await picture.toImage(
      canvasSize.width.round(),
      canvasSize.height.round(),
    );

    layer.bitmap = img;

    _pushUndo(UndoEntry(
      layerIndex: activeLayerIndex,
      oldBitmap: oldBitmap,
      newBitmap: img,
    ));
    _redoStack.clear();

    // Record step for playback
    steps.add(CanvasStep(
      layerIndex: activeLayerIndex,
      brushType: brush,
      color: color,
      size: brushSize,
      points: pts,
      toolMode: tool,
    ));

    _committing = false;
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  // ---------------------------------------------------------------------------
  // Text commit
  // ---------------------------------------------------------------------------
  Future<void> _commitText(String text, Offset pos, double fontSize) async {
    final layer = activeLayer;
    final oldBitmap = layer.bitmap;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (oldBitmap != null) {
      canvas.drawImage(oldBitmap, Offset.zero, Paint());
    }

    final textSpan = TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w500),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, pos);

    final picture = recorder.endRecording();
    final ui.Image img = await picture.toImage(
      canvasSize.width.round(),
      canvasSize.height.round(),
    );

    layer.bitmap = img;

    _pushUndo(UndoEntry(
      layerIndex: activeLayerIndex,
      oldBitmap: oldBitmap,
      newBitmap: img,
    ));
    _redoStack.clear();

    steps.add(CanvasStep(
      layerIndex: activeLayerIndex,
      brushType: brush,
      color: color,
      size: brushSize,
      points: [pos],
      toolMode: ToolMode.text,
      textContent: text,
      textPos: pos,
      textSize: fontSize,
    ));

    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  void _pushUndo(UndoEntry e) {
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

  // ---------------------------------------------------------------------------
  // Shape rendering
  // ---------------------------------------------------------------------------
  void _renderShape(Canvas canvas, Offset start, Offset end, ToolMode mode, _BrushCfg cfg) {
    final paint = Paint()
      ..color = cfg.color
      ..strokeWidth = cfg.size
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    switch (mode) {
      case ToolMode.line:
        canvas.drawLine(start, end, paint);
        break;
      case ToolMode.rect:
        canvas.drawRect(Rect.fromPoints(start, end), paint);
        break;
      case ToolMode.circle:
        final center = (start + end) / 2;
        final r = (end - start).distance / 2;
        canvas.drawCircle(center, r, paint);
        break;
      case ToolMode.ellipse:
        canvas.drawOval(Rect.fromPoints(start, end), paint);
        break;
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Brush rendering — 15+ brushes
  // ---------------------------------------------------------------------------
  void _renderStroke(Canvas canvas, List<Offset> pts, _BrushCfg cfg) {
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _stampDab(canvas, pts.first, cfg, 0, 0);
      return;
    }
    int seed = 1;
    for (int i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final dist = (b - a).distance;
      final step = (cfg.size * 0.15).clamp(0.6, 12.0);
      final n = (dist / step).ceil();
      for (int j = 0; j <= n; j++) {
        final t = n == 0 ? 0.0 : j / n;
        final p = Offset.lerp(a, b, t)!;
        _stampDab(canvas, p, cfg, seed++, j);
      }
    }
    // NOTE: No pen trail/tail — removed per requirement #1.
  }

  void _stampDab(Canvas canvas, Offset p, _BrushCfg cfg, int seed, int sub) {
    final rng = math.Random(seed * 131 + sub * 17);
    switch (cfg.type) {
      case BrushType.pen:
        final r = cfg.size / 2;
        canvas.drawCircle(p, r, Paint()..color = cfg.color..isAntiAlias = true);
        break;

      case BrushType.pencilHard:
        final r = cfg.size / 2 * 0.35;
        for (int k = 0; k < 2; k++) {
          final jx = (rng.nextDouble() - 0.5) * r * 2;
          final jy = (rng.nextDouble() - 0.5) * r * 2;
          canvas.drawCircle(p + Offset(jx, jy), r,
              Paint()..color = cfg.color.withOpacity(0.35));
        }
        break;

      case BrushType.pencilSoft:
        final r = cfg.size / 2 * 0.5;
        final jx = (rng.nextDouble() - 0.5) * r * 1.5;
        final jy = (rng.nextDouble() - 0.5) * r * 1.5;
        canvas.drawCircle(p + Offset(jx, jy), r,
            Paint()..color = cfg.color.withOpacity(0.25));
        break;

      case BrushType.marker:
        canvas.drawCircle(p, cfg.size / 2,
            Paint()..color = cfg.color.withOpacity(0.22));
        break;

      case BrushType.markerThin:
        canvas.drawCircle(p, cfg.size / 4,
            Paint()..color = cfg.color.withOpacity(0.35));
        break;

      case BrushType.markerThick:
        canvas.drawCircle(p, cfg.size / 1.5,
            Paint()..color = cfg.color.withOpacity(0.15));
        break;

      case BrushType.crayon:
        final r = cfg.size / 2;
        canvas.drawCircle(p, r, Paint()..color = cfg.color.withOpacity(0.85));
        canvas.drawCircle(
          p + Offset((rng.nextDouble() - 0.5) * r * 0.25, (rng.nextDouble() - 0.5) * r * 0.25),
          r * 0.55,
          Paint()..color = cfg.color.withOpacity(0.25),
        );
        break;

      case BrushType.watercolor:
        final r = cfg.size / 2;
        for (int k = 0; k < 4; k++) {
          final ang = rng.nextDouble() * 2 * math.pi;
          final rad = rng.nextDouble() * r * 0.6;
          final dp = p + Offset(math.cos(ang), math.sin(ang)) * rad;
          canvas.drawCircle(dp, r * (0.4 + rng.nextDouble() * 0.3),
              Paint()..color = cfg.color.withOpacity(0.08));
        }
        break;

      case BrushType.oil:
        final r = cfg.size / 2;
        canvas.drawCircle(p, r, Paint()..color = cfg.color.withOpacity(0.7));
        canvas.drawCircle(
          p + Offset((rng.nextDouble() - 0.5) * r * 0.3, (rng.nextDouble() - 0.5) * r * 0.3),
          r * 0.7,
          Paint()..color = cfg.color.withOpacity(0.3),
        );
        break;

      case BrushType.chalk:
        final r = cfg.size / 2;
        for (int k = 0; k < 3; k++) {
          final jx = (rng.nextDouble() - 0.5) * r * 0.5;
          final jy = (rng.nextDouble() - 0.5) * r * 0.5;
          canvas.drawCircle(p + Offset(jx, jy), r * 0.6,
              Paint()..color = cfg.color.withOpacity(0.3));
        }
        break;

      case BrushType.charcoal:
        final r = cfg.size / 2 * 0.6;
        for (int k = 0; k < 3; k++) {
          final jx = (rng.nextDouble() - 0.5) * r;
          final jy = (rng.nextDouble() - 0.5) * r;
          canvas.drawCircle(p + Offset(jx, jy), r * 0.5,
              Paint()..color = cfg.color.withOpacity(0.4));
        }
        break;

      case BrushType.glow:
        final r = cfg.size / 2;
        canvas.drawCircle(p, r,
            Paint()..color = cfg.color.withOpacity(0.15)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
        canvas.drawCircle(p, r * 0.5, Paint()..color = cfg.color.withOpacity(0.6));
        break;

      case BrushType.nebula:
        final r = cfg.size / 2;
        for (int k = 0; k < 5; k++) {
          final ang = rng.nextDouble() * 2 * math.pi;
          final rad = rng.nextDouble() * r;
          final dp = p + Offset(math.cos(ang), math.sin(ang)) * rad;
          canvas.drawCircle(dp, r * (0.15 + rng.nextDouble() * 0.25),
              Paint()..color = cfg.color.withOpacity(0.12));
        }
        canvas.drawCircle(p, r * 0.2, Paint()..color = Colors.white.withOpacity(0.5));
        break;

      case BrushType.starlight:
        canvas.drawCircle(p, cfg.size * 0.08, Paint()..color = Colors.white.withOpacity(0.9));
        final r = cfg.size / 2;
        for (int k = 0; k < 2; k++) {
          final ang = rng.nextDouble() * 2 * math.pi;
          final rad = rng.nextDouble() * r;
          final dp = p + Offset(math.cos(ang), math.sin(ang)) * rad;
          canvas.drawCircle(dp, cfg.size * 0.05,
              Paint()..color = cfg.color.withOpacity(0.6));
        }
        break;

      case BrushType.calligraphy:
        final r = cfg.size / 2;
        // Tapering: smaller at dab edges
        final taper = 1.0 - (sub % 10) * 0.03;
        canvas.drawCircle(p, r * taper,
            Paint()..color = cfg.color.withOpacity(0.9));
        break;

      case BrushType.airbrush:
        const n = 8;
        for (int k = 0; k < n; k++) {
          final ang = rng.nextDouble() * 2 * math.pi;
          final rad = rng.nextDouble() * cfg.size / 2;
          final dp = p + Offset(math.cos(ang), math.sin(ang)) * rad;
          canvas.drawCircle(dp, 1.2,
              Paint()..color = cfg.color.withOpacity(0.15));
        }
        break;

      case BrushType.blur:
        // Simulated blur: soft low-alpha circle
        canvas.drawCircle(p, cfg.size / 2,
            Paint()
              ..color = cfg.color.withOpacity(0.06)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        break;

      case BrushType.eraser:
        canvas.drawCircle(p, cfg.size / 2, Paint()..blendMode = BlendMode.clear);
        break;
    }
  }

  /// Paint the current in-progress stroke (live preview).
  void paintLiveStroke(Canvas canvas) {
    if (!_stroking || _stroke.isEmpty) return;
    final cfg = _BrushCfg(type: brush, color: color, size: brushSize);

    if (tool == ToolMode.line || tool == ToolMode.rect || tool == ToolMode.circle || tool == ToolMode.ellipse) {
      if (_shapeStart != null && _stroke.isNotEmpty) {
        _renderShape(canvas, _shapeStart!, _stroke.last, tool, cfg);
      }
      return;
    }

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

  // ---------------------------------------------------------------------------
  // Layer management
  // ---------------------------------------------------------------------------
  void addLayer() {
    if (!layersEnabled) return;
    final newIndex = activeLayerIndex + 1;
    layers.insert(newIndex, PainterLayer(name: '图层 ${layers.length + 1}'));
    activeLayerIndex = newIndex;
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  Future<void> addImageAsLayer(ui.Image image) async {
    if (!layersEnabled) {
      // Degraded mode: draw onto current layer
      final layer = activeLayer;
      final oldBitmap = layer.bitmap;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      if (oldBitmap != null) canvas.drawImage(oldBitmap, Offset.zero, Paint());
      // Fit image into canvas
      final rect = Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height);
      paintImage(canvas: canvas, rect: rect, image: image, fit: BoxFit.cover);
      final pic = recorder.endRecording();
      layer.bitmap = await pic.toImage(canvasSize.width.round(), canvasSize.height.round());
      notifyListeners();
      scheduleMicrotask(() => onProjectChanged?.call());
      return;
    }
    final layer = PainterLayer(name: '图片 ${layers.length + 1}', bitmap: image);
    final newIndex = activeLayerIndex + 1;
    layers.insert(newIndex, layer);
    activeLayerIndex = newIndex;
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  Future<void> importImageAsBase(ui.Image image) async {
    // Import image as a single base layer (flatten onto layer 0)
    for (final l in layers) l.bitmap?.dispose();
    layers.clear();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height);
    paintImage(canvas: canvas, rect: rect, image: image, fit: BoxFit.cover);
    final pic = recorder.endRecording();
    final bmp = await pic.toImage(canvasSize.width.round(), canvasSize.height.round());
    layers.add(PainterLayer(name: '底图', bitmap: bmp));
    activeLayerIndex = 0;
    steps.clear();
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  void deleteLayer(int i) {
    if (layers.length <= 1) return;
    layers[i].bitmap?.dispose();
    layers.removeAt(i);
    if (activeLayerIndex >= layers.length) activeLayerIndex = layers.length - 1;
    else if (activeLayerIndex > i) activeLayerIndex--;
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

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------
  void setBrush(BrushType b) {
    brush = b;
    tool = ToolMode.draw;
    notifyListeners();
  }

  void setTool(ToolMode t) {
    tool = t;
    notifyListeners();
  }

  void setColor(Color c) {
    color = c;
    notifyListeners();
  }

  void setBrushSize(double s) {
    brushSize = s;
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

  /// Clear all layers and start fresh.
  void clearProject() {
    for (final l in layers) l.bitmap?.dispose();
    layers.clear();
    layers.add(PainterLayer(name: '图层 1'));
    activeLayerIndex = 0;
    steps.clear();
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
  }

  /// Callback for auto-save.
  VoidCallback? onProjectChanged;

  /// Replace all layer bitmaps (used when loading a project).
  Future<void> replaceFromLoaded({
    required List<PainterLayer> loadedLayers,
    required int activeIndex,
    List<CanvasStep>? loadedSteps,
  }) async {
    for (final l in layers) l.bitmap?.dispose();
    layers..clear()..addAll(loadedLayers);
    activeLayerIndex = activeIndex.clamp(0, layers.length - 1);
    steps.clear();
    if (loadedSteps != null) steps.addAll(loadedSteps);
    notifyListeners();
  }
}
