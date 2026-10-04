import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import 'paint_engine.dart';

/// Handles persistence of the .pcitrue project and PNG/JPG export.
class ProjectStorage {
  ProjectStorage(this.engine);
  final PaintEngine engine;

  static const String projectDirName = 'pcitrue_project';
  static const String projectFileName = 'project.json';

  Future<Directory> _projectDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, projectDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Save the current project (metadata + per-layer PNG).
  Future<void> saveProject() async {
    final dir = await _projectDir();
    // Clean old layer files.
    await for (final f in dir.list()) {
      if (f is File && f.path.endsWith('.png')) {
        await f.delete();
      }
    }

    final layersJson = <Map<String, dynamic>>[];
    for (var i = 0; i < engine.layers.length; i++) {
      final layer = engine.layers[i];
      String? file;
      if (layer.bitmap != null) {
        final byteData =
            await layer.bitmap!.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          file = 'layer_$i.png';
          await File(p.join(dir.path, file))
              .writeAsBytes(byteData.buffer.asUint8List(), flush: true);
        }
      }
      layersJson.add({
        'name': layer.name,
        'opacity': layer.opacity,
        'visible': layer.visible,
        'file': file,
      });
    }

    final meta = {
      'version': 1,
      'canvasWidth': engine.canvasSize.width,
      'canvasHeight': engine.canvasSize.height,
      'activeLayer': engine.activeLayerIndex,
      'brush': engine.brush.name,
      'color': engine.color.value,
      'brushSize': engine.brushSize,
      'layersEnabled': engine.layersEnabled,
      'layers': layersJson,
    };

    await File(p.join(dir.path, projectFileName))
        .writeAsString(jsonEncode(meta), flush: true);
  }

  /// Load the project if it exists. Returns true when a project was loaded.
  Future<bool> maybeLoadProject() async {
    final dir = await _projectDir();
    final metaFile = File(p.join(dir.path, projectFileName));
    if (!await metaFile.exists()) return false;

    final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    final layersJson = (meta['layers'] as List?) ?? const [];

    final loaded = <PainterLayer>[];
    for (final lj in layersJson) {
      final m = lj as Map<String, dynamic>;
      final layer = PainterLayer(
        name: m['name'] as String? ?? '图层',
        opacity: (m['opacity'] as num?)?.toDouble() ?? 1.0,
        visible: m['visible'] as bool? ?? true,
      );
      final file = m['file'] as String?;
      if (file != null) {
        final f = File(p.join(dir.path, file));
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          layer.bitmap = await _decodeImage(bytes);
        }
      }
      loaded.add(layer);
    }

    if (loaded.isEmpty) return false;

    engine.layersEnabled = meta['layersEnabled'] as bool? ?? true;
    final active = (meta['activeLayer'] as int?) ?? 0;
    await engine.replaceFromLoaded(loadedLayers: loaded, activeIndex: active);

    // Restore brush settings.
    if (meta['color'] != null) {
      engine.setColor(Color(meta['color'] as int));
    }
    if (meta['brushSize'] != null) {
      engine.setBrushSize((meta['brushSize'] as num).toDouble());
    }
    if (meta['brush'] != null) {
      engine.brush = BrushType.values.firstWhere(
        (b) => b.name == meta['brush'],
        orElse: () => BrushType.crayon,
      );
    }
    return true;
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Composite all visible layers onto a white background at canvas resolution.
  Future<ui.Image> _composite() async {
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

  /// Export flattened image. Returns the saved file path.
  Future<String> exportImage({required bool asJpg}) async {
    final composited = await _composite();
    final docs = await getApplicationDocumentsDirectory();
    final stamps = DateTime.now();
    final name =
        'pcitrue_${stamps.year}${stamps.month.toString().padLeft(2, '0')}${stamps.day.toString().padLeft(2, '0')}_'
        '${stamps.hour.toString().padLeft(2, '0')}${stamps.minute.toString().padLeft(2, '0')}${stamps.second.toString().padLeft(2, '0')}';

    if (!asJpg) {
      final byteData = await composited.toByteData(format: ui.ImageByteFormat.png);
      final file = File(p.join(docs.path, '$name.png'));
      await file.writeAsBytes(byteData!.buffer.asUint8List(), flush: true);
      return file.path;
    } else {
      final raw = await composited.toByteData(format: ui.ImageByteFormat.rawRgba);
      final dartImage = img.Image.fromBytes(
        width: composited.width,
        height: composited.height,
        bytes: raw!.buffer,
        order: img.ChannelOrder.rgba,
      );
      final jpgBytes = img.encodeJpg(dartImage, quality: 92);
      final file = File(p.join(docs.path, '$name.jpg'));
      await file.writeAsBytes(jpgBytes, flush: true);
      return file.path;
    }
  }
}
