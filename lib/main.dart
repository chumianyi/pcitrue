import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'canvas_painter.dart';
import 'color_wheel.dart';
import 'paint_engine.dart';
import 'project_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PcitrueApp());
}

class PcitrueApp extends StatefulWidget {
  const PcitrueApp({super.key});

  @override
  State<PcitrueApp> createState() => _PcitrueAppState();
}

class _PcitrueAppState extends State<PcitrueApp> {
  ThemeMode _mode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pcitrue',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: HomeScreen(
        onToggleTheme: () {
          setState(() {
            _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
          });
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onToggleTheme});
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PaintEngine _engine = PaintEngine();
  late final ProjectStorage _storage;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _storage = ProjectStorage(_engine);
    _engine.onProjectChanged = _debouncedSave;
    _init();
  }

  DateTime? _lastSave;
  void _debouncedSave() {
    final now = DateTime.now();
    if (_lastSave != null && now.difference(_lastSave!).inMilliseconds < 800) {
      return;
    }
    _lastSave = now;
    _storage.saveProject();
  }

  Future<void> _init() async {
    // Detect OpenGL ES version -> decide multi-layer vs degraded single layer.
    try {
      const channel = MethodChannel('pcitrue/gl');
      final v = await channel.invokeMethod<String>('getGlEsVersion');
      _engine.glVersion = v ?? 'unknown';
      final major = double.tryParse((v ?? '2.0').split('.').first) ?? 2;
      _engine.layersEnabled = major >= 2.0;
    } catch (_) {
      _engine.layersEnabled = true;
    }

    await _storage.maybeLoadProject();
    if (mounted) {
      setState(() => _ready = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) _engine.resetView(box.size);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pcitrue'),
        actions: [
          ListenableBuilder(
            listenable: _engine,
            builder: (context, _) => IconButton(
              tooltip: '撤销',
              icon: const Icon(Icons.undo),
              onPressed: _engine.canUndo ? _engine.undo : null,
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
          IconButton(
            tooltip: '保存',
            icon: const Icon(Icons.save),
            onPressed: () async {
              await _storage.saveProject();
              _toast('已保存到本地');
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final path = await _storage.exportImage(asJpg: v == 'jpg');
              _toast('已导出 $v: $path');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'png', child: Text('导出 PNG')),
              PopupMenuItem(value: 'jpg', child: Text('导出 JPG')),
            ],
          ),
          IconButton(
            tooltip: '深色/浅色',
            icon: const Icon(Icons.brightness_4),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: _engine,
              builder: (context, _) {
                return Column(
                  children: [
                    if (!_engine.layersEnabled)
                      Container(
                        width: double.infinity,
                        color: Colors.orange.shade100,
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          '设备 OpenGL ES ${_engine.glVersion} 低于 2.0，已切换为单层绘画模式',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            onScaleStart: (d) =>
                                _engine.onScaleStart(d, constraints.biggest),
                            onScaleUpdate: _engine.onScaleUpdate,
                            onScaleEnd: _engine.onScaleEnd,
                            onDoubleTap: () =>
                                _engine.resetView(constraints.biggest),
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
                );
              },
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
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final b in BrushType.values)
                          IconButton(
                            isSelected: _engine.brush == b,
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

  void _openLayerPanel() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) {
          void refresh() => setSheet(() {});
          return ListenableBuilder(
            listenable: _engine,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('图层',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            _engine.addLayer();
                            refresh();
                          },
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
                      // top layer first
                      itemBuilder: (context, i) {
                        final idx = _engine.layers.length - 1 - i;
                        final layer = _engine.layers[idx];
                        final isActive = idx == _engine.activeLayerIndex;
                        return ListTile(
                          selected: isActive,
                          leading: IconButton(
                            icon: Icon(layer.visible
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () {
                              _engine.toggleVisibility(idx);
                              refresh();
                            },
                          ),
                          title: Text(layer.name),
                          subtitle: Slider(
                            min: 0,
                            max: 1,
                            value: layer.opacity,
                            onChanged: (v) {
                              _engine.setLayerOpacity(idx, v);
                              refresh();
                            },
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_upward, size: 20),
                                onPressed: () {
                                  _engine.moveLayerUp(idx);
                                  refresh();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_downward, size: 20),
                                onPressed: () {
                                  _engine.moveLayerDown(idx);
                                  refresh();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: _engine.layers.length > 1
                                    ? () {
                                        _engine.deleteLayer(idx);
                                        refresh();
                                      }
                                    : null,
                              ),
                            ],
                          ),
                          onTap: () {
                            _engine.setActiveLayer(idx);
                            refresh();
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
