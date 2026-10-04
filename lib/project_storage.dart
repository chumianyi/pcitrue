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

/// Metadata for a saved project shown in the home gallery.
class ProjectMeta {
  ProjectMeta({
    required this.id,
    required this.name,
    required this.modifiedAt,
  });

  final String id;
  String name;
  DateTime modifiedAt;
}

/// Multi-project .bin persistence + public Pictures export.
class ProjectStorage {
  ProjectStorage(this.engine);
  final PaintEngine engine;

  static const String _dirName = 'pcitrue_projects';
  static const String _indexName = 'index.json';
  static const MethodChannel _ch = MethodChannel('pcitrue/file');

  String? _projectId;

  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(docs.path, _dirName));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  // ---------------------------------------------------------------------
  Future<List<ProjectMeta>> listProjects() async {
    final root = await _rootDir();
    final f = File(p.join(root.path, _indexName));
    if (!await f.exists()) return [];
    final list = jsonDecode(await f.readAsString()) as List<dynamic>;
    final metas = list
        .map((e) => ProjectMeta(
              id: e['id'] as String,
              name: e['name'] as String? ?? '未命名',
              modifiedAt:
                  DateTime.tryParse(e['modifiedAt'] as String? ?? '') ??
                      DateTime.now(),
            ))
        .toList();
    metas.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return metas;
  }

  Future<void> _writeIndex(List<ProjectMeta> metas) async {
    final root = await _rootDir();
    final f = File(p.join(root.path, _indexName));
    await f.writeAsString(
      jsonEncode(metas
          .map((m) => {
                'id': m.id,
                'name': m.name,
                'modifiedAt': m.modifiedAt.toIso8601String(),
              })
          .toList()),
      flush: true,
    );
  }

  /// Create a brand-new blank project id (engine already blank).
  Future<ProjectMeta> createProject({String? name}) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _projectId = id;
    final now = DateTime.now();
    final meta = ProjectMeta(
      id: id,
      name: name ?? '画作 ${now.month}/${now.day}',
      modifiedAt: now,
    );
    final metas = await listProjects();
    metas.add(meta);
    await _writeIndex(metas);
    await autosave();
    return meta;
  }

  /// Load an existing project into the engine.
  Future<void> openProject(String id) async {
    _projectId = id;
    final root = await _rootDir();
    final bin = File(p.join(root.path, '$id.bin'));
    if (!await bin.exists()) return;
    await _decodeIntoEngine(await bin.readAsBytes());
  }

  Future<Uint8List?> thumbBytes(String id) async {
    final root = await _rootDir();
    final f = File(p.join(root.path, '$id.png'));
    if (await f.exists()) return f.readAsBytes();
    return null;
  }

  Future<void> deleteProject(String id) async {
    final root = await _rootDir();
    for (final ext in ['bin', 'png']) {
      final f = File(p.join(root.path, '$id.$ext'));
      if (await f.exists()) await f.delete();
    }
    final metas = await listProjects();
    metas.removeWhere((m) => m.id == id);
    await _writeIndex(metas);
  }

  /// Decode an imported raster image into a single bottom base layer.
  Future<void> importRasterAsProject(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    await engine.importImageAsBase(frame.image);
  }

  /// Autosave (debounced by caller). Creates entry on first save.
  Future<void> autosave() async {
    var id = _projectId;
    var metas = await listProjects();
    if (id == null || !metas.any((m) => m.id == id)) {
      id = DateTime.now().microsecondsSinceEpoch.toString();
      _projectId = id;
    }

    final root = await _rootDir();
    final bin = await _encodeEngine();
    await File(p.join(root.path, '$id.bin')).writeAsBytes(bin, flush: true);

    final thumb = await _compositeThumb(width: 270);
    if (thumb != null) {
      await File(p.join(root.path, '$id.png')).writeAsBytes(thumb, flush: true);
    }

    metas = await listProjects();
    final i = metas.indexWhere((m) => m.id == id);
    final now = DateTime.now();
    if (i >= 0) {
      metas[i].modifiedAt = now;
    } else {
      metas.add(ProjectMeta(id: id, name: '画作 ${now.month}/${now.day}', modifiedAt: now));
    }
    await _writeIndex(metas);
  }

  // ---------------------------------------------------------------------
  Future<Uint8List> _encodeEngine() async {
    final out = BytesBuilder();
    out.add('PCT1'.codeUnits);
    _u32(out, 1);
    _u32(out, engine.canvasSize.width.round());
    _u32(out, engine.canvasSize.height.round());
    _u32(out, engine.activeLayerIndex);
    _str(out, engine.brush.name);
    _u32(out, engine.color.value);
    _f32(out, engine.brushSize);

    _u32(out, engine.layers.length);
    for (final layer in engine.layers) {
      _str(out, layer.name);
      _f32(out, layer.opacity);
      out.addByte(layer.visible ? 1 : 0);
      if (layer.bitmap != null) {
        final bd = await layer.bitmap!.toByteData(format: ui.ImageByteFormat.png);
        if (bd != null) {
          final bytes = bd.buffer.asUint8List();
          _u32(out, bytes.length);
          out.add(bytes);
        } else {
          _u32(out, 0);
        }
      } else {
        _u32(out, 0);
      }
    }

    _u32(out, engine.textItems.length);
    for (final t in engine.textItems) {
      _str(out, t.text);
      _f32(out, t.pos.dx);
      _f32(out, t.pos.dy);
      _f32(out, t.size);
      _u32(out, t.color.value);
    }
    return out.toBytes();
  }

  Future<void> _decodeIntoEngine(Uint8List bytes) async {
    final r = _Reader(bytes);
    final magic = String.fromCharCodes(r.bytes(4));
    if (magic != 'PCT1') throw const FormatException('不是有效的 Pcitrue .bin 文件');
    r.u32();
    r.u32();
    r.u32();
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
      if (len > 0) layer.bitmap = await _decodeImage(r.bytes(len));
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
      texts.add(TextItem(text: t, pos: Offset(x, y), size: s, color: Color(c)));
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
      canvas.drawImage(layer.bitmap!, Offset.zero,
          Paint()..color = Colors.white.withOpacity(layer.opacity));
    }
    for (final t in engine.textItems) {
      engine.renderTextItem(canvas, t);
    }
    final pic = recorder.endRecording();
    return pic.toImage(engine.canvasSize.width.round(), engine.canvasSize.height.round());
  }

  Future<Uint8List?> _compositeThumb({required int width}) async {
    final full = await _compositeFull();
    final h = (width * full.height / full.width).round();
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
  String _stamp(String ext) {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'pcitrue_${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}.$ext';
  }

  Future<String> exportPng() async {
    final full = await _compositeFull();
    final bd = await full.toByteData(format: ui.ImageByteFormat.png);
    final bytes = bd!.buffer.asUint8List();
    full.dispose();
    return _save(_stamp('png'), 'image/png', bytes);
  }

  Future<String> exportJpg() async {
    final full = await _compositeFull();
    final raw = await full.toByteData(format: ui.ImageByteFormat.rawRgba);
    final dartImg = img.Image.fromBytes(
      width: full.width,
      height: full.height,
      bytes: raw!.buffer,
      order: img.ChannelOrder.rgba,
    );
    final jpg = img.encodeJpg(dartImg, quality: 92);
    full.dispose();
    return _save(_stamp('jpg'), 'image/jpeg', jpg);
  }

  Future<String> exportBin() async {
    final bytes = await _encodeEngine();
    return _save(_stamp('bin'), 'application/octet-stream', bytes);
  }

  Future<String> _save(String filename, String mime, Uint8List bytes) async {
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
void _u32(BytesBuilder b, int v) {
  final l = Uint8List(4);
  l[0] = v & 0xFF;
  l[1] = (v >> 8) & 0xFF;
  l[2] = (v >> 16) & 0xFF;
  l[3] = (v >> 24) & 0xFF;
  b.add(l);
}

void _f32(BytesBuilder b, double v) {
  final d = ByteData(4)..setFloat32(0, v, Endian.little);
  b.add(d.buffer.asUint8List());
}

void _str(BytesBuilder b, String s) {
  final bytes = utf8.encode(s);
  _u32(b, bytes.length);
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

  Uint8List bytes(int n) {
    final v = bytes.sublist(off, off + n);
    off += n;
    return v;
  }

  String str() => utf8.decode(bytes(u32()));
}
