import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import 'paint_engine.dart';

/// Metadata for a single saved project (shown in the home gallery).
class ProjectMeta {
  ProjectMeta({
    required this.id,
    required this.name,
    required this.modifiedAt,
  });

  final String id;
  String name;
  DateTime modifiedAt;

  factory ProjectMeta.fromJson(Map<String, dynamic> j) => ProjectMeta(
        id: j['id'] as String,
        name: j['name'] as String? ?? '未命名',
        modifiedAt:
            DateTime.tryParse(j['modifiedAt'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'modifiedAt': modifiedAt.toIso8601String(),
      };
}

/// Handles the multi-project index, .bin persistence and public export.
class ProjectStorage {
  ProjectStorage(this.engine);
  final PaintEngine engine;

  static const String _rootName = 'pcitrue_projects';
  static const String _indexName = 'index.json';
  static const String _binName = 'project.bin';
  static const String _thumbName = 'thumb.png';

  static const MethodChannel _ch = MethodChannel('pcitrue/file');

  String? _projectId;
  String? get projectId => _projectId;

  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _rootName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _dirFor(String id) async {
    final root = await _rootDir();
    final d = Directory(p.join(root.path, id));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  // ---------------------------------------------------------------------
  // Project index
  // ---------------------------------------------------------------------
  Future<List<ProjectMeta>> listProjects() async {
    final root = await _rootDir();
    final f = File(p.join(root.path, _indexName));
    if (!await f.exists()) return [];
    final list = jsonDecode(await f.readAsString()) as List<dynamic>;
    final metas = list
        .map((e) => ProjectMeta.fromJson(e as Map<String, dynamic>))
        .toList();
    metas.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return metas;
  }

  Future<void> _writeIndex(List<ProjectMeta> metas) async {
    final root = await _rootDir();
    final f = File(p.join(root.path, _indexName));
    await f.writeAsString(
      jsonEncode(metas.map((m) => m.toJson()).toList()),
      flush: true,
    );
  }

  /// Create a brand-new blank project (engine already blank).
  Future<ProjectMeta> createProject({String? name}) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _projectId = id;
    final meta = ProjectMeta(
      id: id,
      name: name ?? '画作 ${DateTime.now().millisecondsSinceEpoch % 100000}',
      modifiedAt: DateTime.now(),
    );
    await _persist(meta);
    return meta;
  }

  /// Start editing an existing project. Loads it into [engine].
  Future<ProjectMeta> openProject(String id) async {
    _projectId = id;
    final metas = await listProjects();
    final meta = metas.firstWhere((m) => m.id == id);
    final dir = await _dirFor(id);
    final bin = File(p.join(dir.path, _binName));
    if (await bin.exists()) {
      final bytes = await bin.readAsBytes();
      await _decodeIntoEngine(bytes);
    }
    return meta;
  }

  /// Persist current engine state into the active project folder.
  Future<void> autosave() async {
    final id = _projectId;
    if (id == null) return;
    final metas = await listProjects();
    final idx = metas.indexWhere((m) => m.id == id);
    ProjectMeta meta;
    if (idx >= 0) {
      meta = metas[idx];
      meta.modifiedAt = DateTime.now();
    } else {
      meta = ProjectMeta(
          id: id, name: '画作 $id', modifiedAt: DateTime.now());
      metas.add(meta);
    }
    await _persist(meta, metas);
  }

  Future<void> renameProject(String id, String name) async {
    final metas = await listProjects();
    final i = metas.indexWhere((m) => m.id == id);
    if (i >= 0) {
      metas[i].name = name;
      await _writeIndex(metas);
    }
  }

  Future<void> deleteProject(String id) async {
    final root = await _rootDir();
    final d = Directory(p.join(root.path, id));
    if (await d.exists()) await d.delete(recursive: true);
    final metas = await listProjects();
    metas.removeWhere((m) => m.id == id);
    await _writeIndex(metas);
  }

  Future<Uint8List?> thumbBytes(String id) async {
    final dir = await _dirFor(id);
    final f = File(p.join(dir.path, _thumbName));
    if (await f.exists()) return f.readAsBytes();
    return null;
  }

  // ---------------------------------------------------------------------
  // .bin encode / decode
  // ---------------------------------------------------------------------
  Future<void> _persist(ProjectMeta meta, [List<ProjectMeta>? existing]) async {
    final dir = await _dirFor(meta.id);
    final bin = await _encodeEngine();
    await File(p.join(dir.path, _binName)).writeAsBytes(bin, flush: true);

    // Thumbnail for the gallery.
    final thumb = await _compositeThumb(width: 270);
    if (thumb != null) {
      await File(p.join(dir.path, _thumbName)).writeAsBytes(thumb, flush: true);
    }

    final metas = existing ?? await listProjects();
    final i = metas.indexWhere((m) => m.id == meta.id);
    if (i >= 0) {
      metas[i] = meta;
    } else {
      metas.add(meta);
    }
    await _writeIndex(metas);
  }

  Future<Uint8List> _encodeEngine() async {
    final out = BytesBuilder();
    out.add('PCT1'.codeUnits);
    _addU32(out, 1); // version
    _addU32(out, engine.canvasSize.width.round());
    _addU32(out, engine.canvasSize.height.round());
    _addU32(out, engine.activeLayerIndex);
    _addStr(out, engine.brush.name);
    _addU32(out, engine.color.value);
    _addF32(out, engine.brushSize);

    // Layers.
    _addU32(out, engine.layers.length);
    for (final layer in engine.layers) {
      _addStr(out, layer.name);
      _addF32(out, layer.opacity);
      out.addByte(layer.visible ? 1 : 0);
      if (layer.bitmap != null) {
        final bd = await layer.bitmap!.toByteData(format: ui.ImageByteFormat.png);
        if (bd != null) {
          final bytes = bd.buffer.asUint8List();
          _addU32(out, bytes.length);
          out.add(bytes);
        } else {
          _addU32(out, 0);
        }
      } else {
        _addU32(out, 0);
      }
    }

    // Text items.
    _addU32(out, engine.textItems.length);
    for (final t in engine.textItems) {
      _addStr(out, t.text);
      _addF32(out, t.pos.dx);
      _addF32(out, t.pos.dy);
      _addF32(out, t.size);
      _addU32(out, t.color.value);
    }

    return out.toBytes();
  }

  Future<void> _decodeIntoEngine(Uint8List bytes) async {
    final r = _Reader(bytes);
    final magic = String.fromCharCodes(r.readBytes(4));
    if (magic != 'PCT1') throw const FormatException('Not a Pcitrue .bin file');
    r.u32(); // version
    r.u32(); // width
    r.u32(); // height
    final active = r.u32();
    final brushName = r.str();
    final colorValue = r.u32();
    final brushSize = r.f32();

    final layerCount = r.u32();
    final layers = <PainterLayer>[];
    for (var i = 0; i < layerCount; i++) {
      final name = r.str();
      final opacity = r.f32();
      final visible = r.byte() == 1;
      final len = r.u32();
      final layer = PainterLayer(name: name, opacity: opacity, visible: visible);
      if (len > 0) {
        layer.bitmap = await _decodeImage(r.readBytes(len));
      }
      layers.add(layer);
    }

    final textCount = r.u32();
    final texts = <TextItem>[];
    for (var i = 0; i < textCount; i++) {
      final t = r.str();
      final x = r.f32();
      final y = r.f32();
      final s = r.f32();
      final c = r.u32();
      texts.add(TextItem(
        text: t,
        pos: Offset(x, y),
        size: s,
        color: Color(c),
      ));
    }

    await engine.replaceFromLoaded(
      loadedLayers: layers,
      activeIndex: active,
      loadedText: texts,
    );
    engine.setColor(Color(colorValue));
    engine.setBrushSize(brushSize);
    engine.brush = BrushType.values.firstWhere(
      (b) => b.name == brushName,
      orElse: () => BrushType.pen,
    );
  }

  /// Decode an imported .bin into the engine (becomes a new project).
  Future<void> importBin(Uint8List bytes) async {
    await _decodeIntoEngine(bytes);
  }

  /// Import a flattened raster image (PNG/JPG bytes) as a single bottom layer.
  Future<void> importRasterAsProject(Uint8List bytes) async {
    engine.clearToBlank();
    final img = await _decodeImage(bytes);
    await engine.addImageAsLayer(img);
  }

  // ---------------------------------------------------------------------
  // Composite / thumbnail
  // ---------------------------------------------------------------------
  Future<ui.Image> _compositeFull() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, engine.canvasSize.width, engine.canvasSize.height),
      Paint()..color = Colors.white,
    );
    for (final layer in engine.layers) {
      if (!layer.visible || layer.bitmap == null) continue;
      canvas.drawImage(
        layer.bitmap!,
        Offset.zero,
        Paint()..color = Colors.white.withOpacity(layer.opacity),
      );
    }
    for (final t in engine.textItems) {
      engine.renderTextItem(canvas, t);
    }
    final pic = recorder.endRecording();
    return pic.toImage(
      engine.canvasSize.width.round(),
      engine.canvasSize.height.round(),
    );
  }

  Future<Uint8List?> _compositeThumb({required int width}) async {
    final full = await _compositeFull();
    final aspect = full.height / full.width;
    final h = (width * aspect).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(width / full.width);
    canvas.drawImage(full, Offset.zero, Paint());
    final pic = recorder.endRecording();
    final thumb = await pic.toImage(width, h);
    final bd = await thumb.toByteData(format: ui.ImageByteFormat.png);
    full.dispose();
    thumb.dispose();
    return bd?.buffer.asUint8List();
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // ---------------------------------------------------------------------
  // Public export -> Pictures/Pcitrue
  // ---------------------------------------------------------------------
  String _stampName(String ext) {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'pcitrue_${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}.$ext';
  }

  Future<String> exportPng() async {
    final full = await _compositeFull();
    final bd = await full.toByteData(format: ui.ImageByteFormat.png);
    full.dispose();
    final bytes = bd!.buffer.asUint8List();
    return _saveToPictures(_stampName('png'), 'image/png', bytes);
  }

  Future<String> exportJpg() async {
    final full = await _compositeFull();
    final raw = await full.toByteData(format: ui.ImageByteFormat.rawRgba);
    full.dispose();
    final dartImg = img.Image.fromBytes(
      width: full.width,
      height: full.height,
      bytes: raw!.buffer,
      order: img.ChannelOrder.rgba,
    );
    final jpg = img.encodeJpg(dartImg, quality: 92);
    return _saveToPictures(_stampName('jpg'), 'image/jpeg', jpg);
  }

  Future<String> exportBin() async {
    final bytes = await _encodeEngine();
    return _saveToPictures(_stampName('bin'), 'application/octet-stream', bytes);
  }

  Future<String> _saveToPictures(
      String filename, String mime, Uint8List bytes) async {
    try {
      await _ch.invokeMethod('ensureLegacyStoragePermission');
    } catch (_) {}
    final rel = await _ch.invokeMethod<String>('saveBytesToPictures', {
      'filename': filename,
      'mime': mime,
      'bytes': bytes,
    });
    return rel ?? 'Pictures/Pcitrue/$filename';
  }
}

// ---------------------------------------------------------------------
// Little-endian binary helpers
// ---------------------------------------------------------------------
void _addU32(BytesBuilder b, int v) {
  final list = Uint8List(4);
  list[0] = v & 0xFF;
  list[1] = (v >> 8) & 0xFF;
  list[2] = (v >> 16) & 0xFF;
  list[3] = (v >> 24) & 0xFF;
  b.add(list);
}

void _addF32(BytesBuilder b, double v) {
  final data = ByteData(4)..setFloat32(0, v, Endian.little);
  b.add(data.buffer.asUint8List());
}

void _addStr(BytesBuilder b, String s) {
  final bytes = utf8.encode(s);
  _addU32(b, bytes.length);
  b.add(bytes);
}

class _Reader {
  _Reader(this.bytes);
  final Uint8List bytes;
  int off = 0;

  int u32() {
    final v = bytes[off] |
        (bytes[off + 1] << 8) |
        (bytes[off + 2] << 16) |
        (bytes[off + 3] << 24);
    off += 4;
    return v;
  }

  double f32() {
    final v = ByteData.sublistView(bytes, off, off + 4).getFloat32(0, Endian.little);
    off += 4;
    return v;
  }

  int byte() => bytes[off++];

  Uint8List readBytes(int n) {
    final v = bytes.sublist(off, off + n);
    off += n;
    return v;
  }

  String str() {
    final n = u32();
    return utf8.decode(readBytes(n));
  }
}
