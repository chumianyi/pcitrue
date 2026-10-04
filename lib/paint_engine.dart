import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Supported brush types.
enum BrushType { crayon, pen, marker, pencil, airbrush, eraser }

extension BrushTypeX on BrushType {
  String get label {
    switch (this) {
      case BrushType.crayon:
        return '蜡笔';
      case BrushType.pen:
        return '钢笔';
      case BrushType.marker:
        return '马克笔';
      case BrushType.pencil:
        return '铅笔';
      case BrushType.airbrush:
        return '喷枪';
      case BrushType.eraser:
        return '橡皮';
    }
  }

  IconData get icon {
    switch (this) {
      case BrushType.crayon:
        return Icons.draw;
      case BrushType.pen:
        return Icons.edit;
      case BrushType.marker:
        return Icons.brush;
      case BrushType.pencil:
        return Icons.create;
      case BrushType.airbrush:
        return Icons.spa;
      case BrushType.eraser:
        return Icons.auto_fix_off;
    }
  }
}

/// A single painting layer. Holds a committed offscreen bitmap.
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

class _UndoEntry {
  _UndoEntry({
    required this.layerIndex,
    required this.oldBitmap,
    required this.newBitmap,
  });
  final int layerIndex;
  final ui.Image? oldBitmap;
  final ui.Image? newBitmap;
}

class _BrushCfg {
  _BrushCfg({
    required this.type,
    required this.color,
    required this.size,
  });
  final BrushType type;
  final Color color;
  final double size;
}

enum _GestureMode { none, draw, transform }

/// The core painting engine. Owns the layer stack, current brush, transform
/// (pan/zoom), undo/redo and persistence hooks.
class PaintEngine extends ChangeNotifier {
  PaintEngine() {
    layers.add(PainterLayer(name: '图层 1'));
  }

  // ---- Canvas ----
  final Size canvasSize = const Size(1080, 1920);

  // ---- Layers ----
  final List<PainterLayer> layers = [];
  int activeLayerIndex = 0;

  /// Whether multi-layer painting is available. Disabled when the device does
  /// not support OpenGL ES 2.0+ (degraded single-layer mode).
  bool layersEnabled = true;
  String glVersion = 'unknown';

  // ---- Current brush ----
  BrushType brush = BrushType.crayon;
  Color color = const Color(0xFF1A73E8);
  double brushSize = 14.0;

  // ---- Transform (screen space) ----
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double get scale => _scale;
  Offset get offset => _offset;

  // ---- In-progress stroke ----
  final List<Offset> _stroke = [];
  bool _stroking = false;
  bool get stroking => _stroking;
  List<Offset> get strokePoints => List.unmodifiable(_stroke);

  // ---- Gesture bookkeeping ----
  _GestureMode _mode = _GestureMode.none;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;

  // ---- Undo / redo ----
  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];
  static const int _maxUndo = 25;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  bool _committing = false;

  PainterLayer get activeLayer => layers[activeLayerIndex];

  // ---------------------------------------------------------------------
  // Coordinate conversion
  // ---------------------------------------------------------------------
  Offset screenToCanvas(Offset screen) => (screen - _offset) / _scale;

  void _clampTransform() {
    _scale = _scale.clamp(0.1, 6.0);
  }

  // ---------------------------------------------------------------------
  // Gesture handlers (wired to a GestureDetector)
  // ---------------------------------------------------------------------
  void onScaleStart(ScaleStartDetails details, Size viewport) {
    if (details.pointerCount >= 2) {
      _mode = _GestureMode.transform;
      // If a stroke was in progress, finalize it before transforming.
      if (_stroking) {
        _commitStroke();
      }
      _baseScale = _scale;
      _baseOffset = _offset;
      return;
    }

    // Single pointer -> begin a stroke.
    _mode = _GestureMode.draw;
    final p = screenToCanvas(details.localFocalPoint);
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

    if (_mode == _GestureMode.draw && _stroking) {
      final p = screenToCanvas(details.localFocalPoint);
      // Ignore tiny jitter.
      if (_stroke.isEmpty || (p - _stroke.last).distance > 0.5) {
        _stroke.add(p);
        notifyListeners();
      }
    }
  }

  void onScaleEnd(ScaleEndDetails details) {
    if (_mode == _GestureMode.draw && _stroking) {
      _commitStroke();
    }
    _mode = _GestureMode.none;
  }

  // ---------------------------------------------------------------------
  // Stroke baking
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
    if (oldBitmap != null) {
      canvas.drawImage(oldBitmap, Offset.zero, Paint());
    }

    final cfg = _BrushCfg(type: brush, color: color, size: brushSize);
    _renderStroke(canvas, pts, cfg, addTail: true);

    final picture = recorder.endRecording();
    final ui.Image img = await picture.toImage(
      canvasSize.width.round(),
      canvasSize.height.round(),
    );

    layer.bitmap = img;

    // Undo bookkeeping.
    _pushUndo(_UndoEntry(
      layerIndex: activeLayerIndex,
      oldBitmap: oldBitmap,
      newBitmap: img,
    ));
    _redoStack.clear();

    _committing = false;
    notifyListeners();
    // Auto-save after a stroke settles.
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
  // Brush rendering
  // ---------------------------------------------------------------------
  void _renderStroke(Canvas canvas, List<Offset> pts, _BrushCfg cfg,
      {bool addTail = false}) {
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
    if (addTail && cfg.type == BrushType.pen && pts.length >= 2) {
      _drawPenTail(canvas, pts, cfg);
    }
  }

  void _drawPenTail(Canvas canvas, List<Offset> pts, _BrushCfg cfg) {
    final a = pts[pts.length - 2];
    final b = pts.last;
    final dir = b - a;
    if (dir.distance < 1.0) return;
    final d = dir / dir.distance;
    final tailLen = cfg.size * 3.5;
    final end = b + d * tailLen;
    final paint = Paint()
      ..color = cfg.color.withOpacity(0.35)
      ..strokeWidth = cfg.size * 0.35
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(b, end, paint);
  }

  void _stampDab(Canvas canvas, Offset p, _BrushCfg cfg, int seed, int sub) {
    final rng = math.Random(seed * 131 + sub * 17);
    switch (cfg.type) {
      case BrushType.crayon:
        final r = cfg.size / 2;
        final jx = (rng.nextDouble() - 0.5) * r * 0.25;
        final jy = (rng.nextDouble() - 0.5) * r * 0.25;
        canvas.drawCircle(
          p,
          r,
          Paint()..color = cfg.color.withOpacity(0.85),
        );
        // Grain speckle for the rough crayon feel.
        canvas.drawCircle(
          p + Offset(jx, jy),
          r * 0.55,
          Paint()..color = cfg.color.withOpacity(0.25),
        );
        break;
      case BrushType.pen:
        final r = cfg.size / 2;
        canvas.drawCircle(
          p,
          r,
          Paint()
            ..color = cfg.color
            ..isAntiAlias = true,
        );
        break;
      case BrushType.marker:
        canvas.drawCircle(
          p,
          cfg.size / 2,
          Paint()..color = cfg.color.withOpacity(0.22),
        );
        break;
      case BrushType.pencil:
        final r = cfg.size / 2 * 0.45;
        final jx = (rng.nextDouble() - 0.5) * r * 1.5;
        final jy = (rng.nextDouble() - 0.5) * r * 1.5;
        canvas.drawCircle(
          p + Offset(jx, jy),
          r,
          Paint()..color = cfg.color.withOpacity(0.5),
        );
        break;
      case BrushType.airbrush:
        const n = 6;
        for (int k = 0; k < n; k++) {
          final ang = rng.nextDouble() * 2 * math.pi;
          final rad = rng.nextDouble() * cfg.size / 2;
          final dp = p + Offset(math.cos(ang), math.sin(ang)) * rad;
          canvas.drawCircle(
            dp,
            0.9,
            Paint()..color = cfg.color.withOpacity(0.18),
          );
        }
        break;
      case BrushType.eraser:
        canvas.drawCircle(
          p,
          cfg.size / 2,
          Paint()..blendMode = BlendMode.clear,
        );
        break;
    }
  }

  /// Paint the current in-progress stroke (live preview) onto [canvas].
  void paintLiveStroke(Canvas canvas) {
    if (!_stroking || _stroke.isEmpty) return;
    final cfg = _BrushCfg(type: brush, color: color, size: brushSize);
    if (brush == BrushType.eraser) {
      // Isolate erasing to the active layer buffer.
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

  // ---------------------------------------------------------------------
  // Layer management
  // ---------------------------------------------------------------------
  void addLayer() {
    if (!layersEnabled) return;
    final newIndex = activeLayerIndex + 1;
    layers.insert(newIndex, PainterLayer(name: '图层 ${layers.length + 1}'));
    activeLayerIndex = newIndex;
    notifyListeners();
    scheduleMicrotask(() => onProjectChanged?.call());
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
  // Settings
  // ---------------------------------------------------------------------
  void setBrush(BrushType b) {
    brush = b;
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
    // Fit canvas into viewport.
    final scaleX = viewport.width / canvasSize.width;
    final scaleY = viewport.height / canvasSize.height;
    _scale = math.min(scaleX, scaleY);
    _offset = Offset(
      (viewport.width - canvasSize.width * _scale) / 2,
      (viewport.height - canvasSize.height * _scale) / 2,
    );
    notifyListeners();
  }

  /// Callback invoked whenever the project changes (for auto-save).
  VoidCallback? onProjectChanged;

  /// Replace all layer bitmaps (used when loading a project).
  Future<void> replaceFromLoaded({
    required List<PainterLayer> loadedLayers,
    required int activeIndex,
  }) async {
    for (final l in layers) {
      l.bitmap?.dispose();
    }
    layers
      ..clear()
      ..addAll(loadedLayers);
    activeLayerIndex = activeIndex.clamp(0, layers.length - 1);
    notifyListeners();
  }
}
