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

/// Handles .bin binary project storage and public folder export.
class ProjectStorage {
  ProjectStorage(this.engine);
  final PaintEngine engine;

  static const String projectsDirName = 'pcitrue_projects';
  static const MethodChannel _storageChannel = MethodChannel('pcitrue/storage');

  // ---- Private project directory (auto-save) ----
  Future<Directory> _projectsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, projectsDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ---- List all saved projects ----
  Future<List<ProjectMeta>> listProjects() async {
    final dir = await _projectsDir();
    final metas = <ProjectMeta>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.bin')) {
        final stat = await entity.stat();
        final name = p.basenameWithoutExtension(entity.path);
        // Try to read thumbnail
        final thumbFile = File('${entity.path}.thumb.png');
        ui.Image? thumb;
        if (await thumbFile.exists()) {
          thumb = await _decodeImage(await thumbFile.readAsBytes());
        }
        metas.add(ProjectMeta(
          fileName: p.basename(entity.path),
          displayName: name,
          modified: stat.modified,
          thumbnail: thumb,
        ));
      }
    }
    metas.sort((a, b) => b.modified.compareTo(a.modified));
    return metas;
  }

  /// Save current project as a .bin file. If [projectName] is null, uses
  /// the currently loaded project name or creates a new timestamped one.
  String? currentProjectName;

  Future<String> saveProjectAsBin({String? name}) async {
    final dir = await _projectsDir();
    final stamp = DateTime.now();
    final fileName = name ??
        currentProjectName ??
        'painting_${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}_'
            '${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}${stamp.second.toString().padLeft(2, '0')}';
    final binFile = File(p.join(dir.path, '$fileName.bin'));
    currentProjectName = fileName;

    final bytes = await _serializeToBin();
    await binFile.writeAsBytes(bytes, flush: true);

    // Save thumbnail
    final thumb = await _composite(maxWidth: 200);
    final td = await thumb.toByteData(format: ui.ImageByteFormat.png);
    if (td != null) {
      await File('${binFile.path}.thumb.png')
          .writeAsBytes(td.buffer.asUint8List(), flush: true);
    }
    return fileName;
  }

  /// Auto-save to current project (debounced by caller).
  Future<void> autoSave() async {
    if (currentProjectName == null) {
      await saveProjectAsBin();
    } else {
      await saveProjectAsBin(name: currentProjectName);
    }
  }

  // ===========================================================================
  // .BIN Binary serialization
  // ===========================================================================
  Future<Uint8List> _serializeToBin() async {
    final builder = BytesBuilder();

    // Header
    builder.add(utf8.encode('PCITRUE1')); // 8-byte magic
    _writeInt32(builder, 2); // version

    // Canvas size
    _writeInt32(builder, engine.canvasSize.width.round());
    _writeInt32(builder, engine.canvasSize.height.round());

    // Active layer
    _writeInt32(builder, engine.activeLayerIndex);

    // Brush settings
    _writeInt32(builder, engine.brush.index);
    _writeInt32(builder, engine.color.value);
    _writeFloat64(builder, engine.brushSize);

    // Layers
    _writeInt32(builder, engine.layers.length);
    for (final layer in engine.layers) {
      _writeString(builder, layer.name);
      _writeFloat64(builder, layer.opacity);
      builder.addByte(layer.visible ? 1 : 0);
      if (layer.bitmap != null) {
        final bd = await layer.bitmap!.toByteData(format: ui.ImageByteFormat.png);
        if (bd != null) {
          final pngBytes = bd.buffer.asUint8List();
          _writeInt32(builder, pngBytes.length);
          builder.add(pngBytes);
        } else {
          _writeInt32(builder, 0);
        }
      } else {
        _writeInt32(builder, 0);
      }
    }

    // Steps
    _writeInt32(builder, engine.steps.length);
    for (final step in engine.steps) {
      _writeInt32(builder, step.layerIndex);
      _writeInt32(builder, step.brushType.index);
      _writeInt32(builder, step.color.value);
      _writeFloat64(builder, step.size);
      _writeInt32(builder, step.toolMode.index);
      _writeInt32(builder, step.points.length);
      for (final pt in step.points) {
        _writeFloat64(builder, pt.dx);
        _writeFloat64(builder, pt.dy);
      }
      // Text data
      if (step.textContent != null) {
        builder.addByte(1);
        _writeString(builder, step.textContent!);
        _writeFloat64(builder, step.textPos?.dx ?? 0);
        _writeFloat64(builder, step.textPos?.dy ?? 0);
        _writeFloat64(builder, step.textSize ?? 32);
      } else {
        builder.addByte(0);
      }
    }

    return builder.toBytes();
  }

  Future<void> loadProjectFromBin(String fileName) async {
    final dir = await _projectsDir();
    final file = File(p.join(dir.path, fileName));
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    await _deserializeFromBin(bytes);
    currentProjectName = p.basenameWithoutExtension(fileName);
  }

  Future<void> _deserializeFromBin(Uint8List bytes) async {
    var pos = 0;
    String magic = utf8.decode(bytes.sublist(0, 8));
    pos = 8;
    if (magic != 'PCITRUE1') throw FormatException('Not a Pcitrue .bin file');

    final version = _readInt32(bytes, pos); pos += 4;
    final canvasW = _readInt32(bytes, pos); pos += 4;
    final canvasH = _readInt32(bytes, pos); pos += 4;
    final activeIdx = _readInt32(bytes, pos); pos += 4;
    final brushIdx = _readInt32(bytes, pos); pos += 4;
    final colorVal = _readInt32(bytes, pos); pos += 4;
    final brushSize = _readFloat64(bytes, pos); pos += 8;

    final layerCount = _readInt32(bytes, pos); pos += 4;
    final layers = <PainterLayer>[];
    for (var i = 0; i < layerCount; i++) {
      final name = _readString(bytes, pos); pos += _stringLen(name);
      final opacity = _readFloat64(bytes, pos); pos += 8;
      final visible = bytes[pos] == 1; pos += 1;
      final pngLen = _readInt32(bytes, pos); pos += 4;
      ui.Image? bmp;
      if (pngLen > 0) {
        final pngBytes = bytes.sublist(pos, pos + pngLen);
        bmp = await _decodeImage(pngBytes);
        pos += pngLen;
      }
      layers.add(PainterLayer(name: name, opacity: opacity, visible: visible, bitmap: bmp));
    }

    // Steps
    final stepCount = _readInt32(bytes, pos); pos += 4;
    final steps = <CanvasStep>[];
    for (var i = 0; i < stepCount; i++) {
      final li = _readInt32(bytes, pos); pos += 4;
      final bi = _readInt32(bytes, pos); pos += 4;
      final cv = _readInt32(bytes, pos); pos += 4;
      final sz = _readFloat64(bytes, pos); pos += 8;
      final tm = _readInt32(bytes, pos); pos += 4;
      final ptCount = _readInt32(bytes, pos); pos += 4;
      final pts = <Offset>[];
      for (var j = 0; j < ptCount; j++) {
        final x = _readFloat64(bytes, pos); pos += 8;
        final y = _readFloat64(bytes, pos); pos += 8;
        pts.add(Offset(x, y));
      }
      String? textContent;
      Offset? textPos;
      double? textSize;
      final hasText = bytes[pos] == 1; pos += 1;
      if (hasText) {
        textContent = _readString(bytes, pos); pos += _stringLen(textContent);
        final tx = _readFloat64(bytes, pos); pos += 8;
        final ty = _readFloat64(bytes, pos); pos += 8;
        textSize = _readFloat64(bytes, pos); pos += 8;
        textPos = Offset(tx, ty);
      }
      steps.add(CanvasStep(
        layerIndex: li,
        brushType: BrushType.values[bi],
        color: Color(cv),
        size: sz,
        points: pts,
        toolMode: ToolMode.values[tm],
        textContent: textContent,
        textPos: textPos,
        textSize: textSize,
      ));
    }

    await engine.replaceFromLoaded(
      loadedLayers: layers,
      activeIndex: activeIdx,
      loadedSteps: steps,
    );
    engine.brush = BrushType.values[brushIdx.clamp(0, BrushType.values.length - 1)];
    engine.setColor(Color(colorVal));
    engine.setBrushSize(brushSize);
  }

  // ---- Binary helpers ----
  void _writeInt32(BytesBuilder b, int v) {
    final data = ByteData(4);
    data.setInt32(0, v, Endian.little);
    b.add(data.buffer.asUint8List());
  }

  void _writeFloat64(BytesBuilder b, double v) {
    final data = ByteData(8);
    data.setFloat64(0, v, Endian.little);
    b.add(data.buffer.asUint8List());
  }

  void _writeString(BytesBuilder b, String s) {
    final bytes = utf8.encode(s);
    _writeInt32(b, bytes.length);
    b.add(bytes);
  }

  int _readInt32(Uint8List b, int pos) =>
      ByteData.sublistView(b, pos, pos + 4).getInt32(0, Endian.little);

  double _readFloat64(Uint8List b, int pos) =>
      ByteData.sublistView(b, pos, pos + 8).getFloat64(0, Endian.little);

  String _readString(Uint8List b, int pos) {
    final len = _readInt32(b, pos);
    return utf8.decode(b.sublist(pos + 4, pos + 4 + len));
  }

  int _stringLen(String s) => 4 + utf8.encode(s).length;

  // ===========================================================================
  // Export to PUBLIC Pcitrue folder
  // ===========================================================================
  Future<ui.Image> _composite({int? maxWidth}) async {
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
    final pic = recorder.endRecording();
    return pic.toImage(
      engine.canvasSize.width.round(),
      engine.canvasSize.height.round(),
    );
  }

  /// Export PNG/JPG to the PUBLIC Pcitrue folder (Download/Pcitrue).
  /// Returns the display path.
  Future<String> exportToPublic({required bool asJpg}) async {
    final composited = await _composite();
    final stamp = DateTime.now();
    final ext = asJpg ? 'jpg' : 'png';
    final mime = asJpg ? 'image/jpeg' : 'image/png';
    final fileName = 'Pcitrue_${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}_'
        '${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}${stamp.second.toString().padLeft(2, '0')}.$ext';

    late Uint8List fileBytes;
    if (!asJpg) {
      final bd = await composited.toByteData(format: ui.ImageByteFormat.png);
      fileBytes = bd!.buffer.asUint8List();
    } else {
      final raw = await composited.toByteData(format: ui.ImageByteFormat.rawRgba);
      final dartImage = img.Image.fromBytes(
        width: composited.width,
        height: composited.height,
        bytes: raw!.buffer,
        order: img.ChannelOrder.rgba,
      );
      fileBytes = img.encodeJpg(dartImage, quality: 92);
    }

    // Use method channel to save to public Pcitrue folder
    final result = await _storageChannel.invokeMethod('saveToPublicPcitrue', {
      'fileName': fileName,
      'bytes': fileBytes,
      'mimeType': mime,
    });
    return result as String;
  }

  /// Export .bin project file to public Pcitrue folder.
  Future<String> exportBinToPublic() async {
    final stamp = DateTime.now();
    final fileName = 'Pcitrue_project_${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}_'
        '${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}${stamp.second.toString().padLeft(2, '0')}.bin';

    final bytes = await _serializeToBin();
    final result = await _storageChannel.invokeMethod('saveToPublicPcitrue', {
      'fileName': fileName,
      'bytes': bytes,
      'mimeType': 'application/octet-stream',
    });
    return result as String;
  }

  /// Delete a project file.
  Future<void> deleteProject(String fileName) async {
    final dir = await _projectsDir();
    final f = File(p.join(dir.path, fileName));
    if (await f.exists()) await f.delete();
    final thumb = File('${f.path}.thumb.png');
    if (await thumb.exists()) await thumb.delete();
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

/// Metadata for a project in the home gallery.
class ProjectMeta {
  ProjectMeta({
    required this.fileName,
    required this.displayName,
    required this.modified,
    this.thumbnail,
  });
  final String fileName;
  final String displayName;
  final DateTime modified;
  final ui.Image? thumbnail;
}
