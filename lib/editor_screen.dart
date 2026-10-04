import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'canvas_painter.dart';
import 'color_wheel.dart';
import 'paint_engine.dart';
import 'project_storage.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.engine, required this.storage});
  final PaintEngine engine;
  final ProjectStorage storage;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final PaintEngine _engine;
  late final ProjectStorage _storage;

  DateTime? _lastSave;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine;
    _storage = widget.storage;
    _engine.onProjectChanged = _debouncedSave;
    _engine.onTextTap = _placeText;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) _engine.resetView(box.size);
    });
  }

  String? _pendingText;
  double _pendingTextSize = 32;
  Color _pendingTextColor = const Color(0xFF1A73E8);

  void _debouncedSave() {
    final now = DateTime.now();
    if (_lastSave != null && now.difference(_lastSave!).inMilliseconds < 800) return;
    _lastSave = now;
    _storage.autosave();
  }

  void _placeText(Offset canvasPoint) {
    if (_pendingText == null || _pendingText!.isEmpty) return;
    _engine.addTextItem(TextItem(
      text: _pendingText!,
      pos: canvasPoint,
      size: _pendingTextSize,
      color: _pendingTextColor,
    ));
    _pendingText = null;
    _toast('文字已放置');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _storage.autoSave();
            if (mounted) Navigator.pop(context);
          },
        ),
        title: const Text('编辑'),
        actions: [
          ListenableBuilder(
            listenable: _engine,
            builder: (context, _) => GestureDetector(
              onLongPress: _openStepTimeline,
              child: IconButton(
                tooltip: '撤销 (长按查看步骤)',
                icon: const Icon(Icons.undo),
                onPressed: _engine.canUndo ? _engine.undo : null,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _engine,
            builder: (context, _) => IconButton(
              tooltip: '重做',
              icon: const Icon(Icons.redo),
              onPressed: _engine.canRedo ? _engine.redo : null,
            ),
          ),
          IconButton(
            tooltip: '图层',
            icon: const Icon(Icons.layers),
            onPressed: _engine.layersEnabled ? _openLayerPanel : null,
          ),
          PopupMenuButton<String>(
            onSelected: _handleExport,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'png', child: Text('导出 PNG')),
              PopupMenuItem(value: 'jpg', child: Text('导出 JPG')),
              PopupMenuItem(value: 'bin', child: Text('导出工程 .bin')),
              PopupMenuItem(value: 'import_layer', child: Text('叠加图片为图层')),
              PopupMenuItem(value: 'clear', child: Text('清空画布')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_engine.layersEnabled)
            Container(
              width: double.infinity,
              color: Colors.orange.shade100,
              padding: const EdgeInsets.all(6),
              child: Text(
                '设备 OpenGL ES ${_engine.glVersion} 低于 2.0，单层模式',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onScaleStart: (d) => _engine.onScaleStart(d, constraints.biggest),
                  onScaleUpdate: _engine.onScaleUpdate,
                  onScaleEnd: _engine.onScaleEnd,
                  onDoubleTap: () => _engine.resetView(constraints.biggest),
                  child: Container(
                    color: const Color(0xFF222222),
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: CanvasPainter(engine: _engine),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  _colorButton(),
                  IconButton(
                    isSelected: _engine.tool == Tool.line,
                    icon: const Icon(Icons.straighten),
                    selectedIcon: Icon(Icons.straighten, color: scheme.primary),
                    tooltip: '直线',
                    onPressed: () => _engine.setTool(Tool.line),
                  ),
                  IconButton(
                    isSelected: _engine.tool == Tool.rect,
                    icon: const Icon(Icons.crop_square),
                    selectedIcon: Icon(Icons.crop_square, color: scheme.primary),
                    tooltip: '矩形',
                    onPressed: () => _engine.setTool(Tool.rect),
                  ),
                  IconButton(
                    isSelected: _engine.tool == Tool.ellipse,
                    icon: const Icon(Icons.circle_outlined),
                    selectedIcon: Icon(Icons.circle_outlined, color: scheme.primary),
                    tooltip: '椭圆',
                    onPressed: () => _engine.setTool(Tool.ellipse),
                  ),
                  IconButton(
                    isSelected: _engine.tool == Tool.text,
                    icon: const Icon(Icons.text_fields),
                    selectedIcon: Icon(Icons.text_fields, color: scheme.primary),
                    tooltip: '文字',
                    onPressed: _openTextDialog,
                  ),
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final b in BrushType.values)
                          IconButton(
                            isSelected: _engine.brush == b && _engine.tool == Tool.draw,
                            selectedIcon: Icon(b.icon, color: scheme.primary),
                            icon: Icon(b.icon),
                            tooltip: b.label,
                            onPressed: () => _engine.setBrush(b),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                const Icon(Icons.line_weight, size: 20),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 60,
                    value: _engine.brushSize.clamp(1, 60),
                    onChanged: _engine.setBrushSize,
                  ),
                ),
                IconButton(
                  tooltip: '适应屏幕',
                  icon: const Icon(Icons.fit_screen),
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box != null) _engine.resetView(box.size);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorButton() {
    return GestureDetector(
      onTap: _openColorWheel,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: _engine.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
        ),
      ),
    );
  }

  void _openColorWheel() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: ColorWheelPicker(
          initialColor: _engine.color,
          onChanged: (c) => _engine.setColor(c),
        ),
      ),
    );
  }

  void _openTextDialog() async {
    final controller = TextEditingController();
    double textSize = 32;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: const Text('插入文字'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: '输入文字'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('大小'),
                  Expanded(
                    child: Slider(
                      min: 12,
                      max: 100,
                      value: textSize,
                      onChanged: (v) {
                        textSize = v;
                        setS(() {});
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(context, {'text': controller.text, 'size': textSize}),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (result != null && result['text']?.isNotEmpty == true) {
      _pendingText = result['text'] as String;
      _pendingTextSize = result['size'] as double;
      _pendingTextColor = _engine.color;
      _engine.setTool(Tool.text);
      if (mounted) _toast('点击画布放置文字');
    }
  }

  void _openLayerPanel() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) {
          void refresh() => setSheet(() {});
          return ListenableBuilder(
            listenable: _engine,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('图层', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      FilledButton.tonalIcon(
                        onPressed: () { _engine.addLayer(); refresh(); },
                        icon: const Icon(Icons.add),
                        label: const Text('新建'),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 260,
                  child: ListView.builder(
                    itemCount: _engine.layers.length,
                    itemBuilder: (context, i) {
                      final idx = _engine.layers.length - 1 - i;
                      final layer = _engine.layers[idx];
                      final isActive = idx == _engine.activeLayerIndex;
                      return ListTile(
                        selected: isActive,
                        leading: IconButton(
                          icon: Icon(layer.visible ? Icons.visibility : Icons.visibility_off),
                          onPressed: () { _engine.toggleVisibility(idx); refresh(); },
                        ),
                        title: Text(layer.name),
                        subtitle: Slider(
                          min: 0, max: 1, value: layer.opacity,
                          onChanged: (v) { _engine.setLayerOpacity(idx, v); refresh(); },
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.arrow_upward, size: 20), onPressed: () { _engine.moveLayerUp(idx); refresh(); }),
                            IconButton(icon: const Icon(Icons.arrow_downward, size: 20), onPressed: () { _engine.moveLayerDown(idx); refresh(); }),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: _engine.layers.length > 1 ? () { _engine.deleteLayer(idx); refresh(); } : null,
                            ),
                          ],
                        ),
                        onTap: () { _engine.setActiveLayer(idx); refresh(); },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openStepTimeline() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => _StepTimeline(engine: _engine),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _handleExport(String v) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      switch (v) {
        case 'png':
          final path = await _storage.exportPng();
          _toast('已保存到 Pcitrue 文件夹: $path');
          break;
        case 'jpg':
          final path = await _storage.exportJpg();
          _toast('已保存到 Pcitrue 文件夹: $path');
          break;
        case 'bin':
          final path = await _storage.exportBin();
          _toast('工程已导出到 Pcitrue 文件夹: $path');
          break;
        case 'import_layer':
          await _pickImageAsLayer();
          break;
        case 'clear':
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('清空画布'),
              content: const Text('确定要清空所有图层吗？'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
              ],
            ),
          );
          if (ok == true) _engine.clearToBlank();
          break;
      }
    } catch (e) {
      _toast('操作失败: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickImageAsLayer() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    await _engine.addImageAsLayer(frame.image);
    if (mounted) _toast('图片已作为新图层添加');
  }
}

// =============================================================================
// Step Timeline
// =============================================================================
class _StepTimeline extends StatefulWidget {
  const _StepTimeline({required this.engine});
  final PaintEngine engine;

  @override
  State<_StepTimeline> createState() => _StepTimelineState();
}

class _StepTimelineState extends State<_StepTimeline> {
  double _progress = 0;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _progress = widget.engine.steps.length.toDouble();
  }

  Future<void> _playback() async {
    if (_playing) return;
    setState(() => _playing = true);
    final total = widget.engine.steps.length;
    for (int i = 0; i <= total; i++) {
      if (!mounted) return;
      setState(() => _progress = i.toDouble());
      await Future.delayed(const Duration(milliseconds: 300));
    }
    setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.engine.steps.length;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('步骤回放', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('共 $total 步', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                onPressed: _playing ? null : _playback,
              ),
              Expanded(
                child: Slider(
                  min: 0,
                  max: total.toDouble().clamp(1, 9999),
                  value: _progress.clamp(0, total.toDouble()),
                  onChanged: (v) => setState(() => _progress = v),
                ),
              ),
              Text('${_progress.round()}/$total'),
            ],
          ),
        ],
      ),
    );
  }
}
