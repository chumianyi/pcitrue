import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'paint_engine.dart';
import 'project_storage.dart';
import 'editor_screen.dart';
import 'tutorial_screen.dart';

/// Home gallery: shows all paintings as thumbnails, with New and Import buttons.
class HomeGallery extends StatefulWidget {
  const HomeGallery({super.key, required this.onToggleTheme});
  final VoidCallback onToggleTheme;

  @override
  State<HomeGallery> createState() => _HomeGalleryState();
}

class _HomeGalleryState extends State<HomeGallery> {
  List<ProjectMeta> _projects = [];
  bool _loading = true;
  final Map<String, ui.Image?> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final storage = ProjectStorage(PaintEngine());
    final projects = await storage.listProjects();
    final thumbs = <String, ui.Image?>{};
    for (final p in projects) {
      final tb = await storage.thumbBytes(p.id);
      if (tb != null) {
        final codec = await ui.instantiateImageCodec(tb);
        final frame = await codec.getNextFrame();
        thumbs[p.id] = frame.image;
      } else {
        thumbs[p.id] = null;
      }
    }
    setState(() {
      _projects = projects;
      _thumbs..clear()..addAll(thumbs);
      _loading = false;
    });
  }

  Future<void> _newPainting() async {
    final engine = PaintEngine();
    final storage = ProjectStorage(engine);
    await storage.createProject();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(engine: engine, storage: storage)),
    );
    _refresh();
  }

  Future<void> _openProject(ProjectMeta meta) async {
    final engine = PaintEngine();
    final storage = ProjectStorage(engine);
    try {
      await storage.openProject(meta.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打开失败: $e')));
      }
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(engine: engine, storage: storage)),
    );
    _refresh();
  }

  Future<void> _importImage() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();

    final engine = PaintEngine();
    final storage = ProjectStorage(engine);
    await storage.importRasterAsProject(bytes);
    await storage.createProject(name: '导入画');
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(engine: engine, storage: storage)),
    );
    _refresh();
  }

  Future<void> _openTutorial() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TutorialScreen()),
    );
  }

  Future<void> _confirmDelete(ProjectMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除画作'),
        content: Text('确定要删除「${meta.name}」吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      final storage = ProjectStorage(PaintEngine());
      await storage.deleteProject(meta.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pcitrue'),
        actions: [
          IconButton(
            tooltip: '教程',
            icon: const Icon(Icons.help_outline),
            onPressed: _openTutorial,
          ),
          IconButton(
            tooltip: '深色/浅色',
            icon: const Icon(Icons.brightness_4),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.75,
                ),
                itemCount: _projects.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return _buildNewButton();
                  final meta = _projects[i - 1];
                  return _buildProjectCard(meta);
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importImage,
        icon: const Icon(Icons.file_upload),
        label: const Text('导入画'),
      ),
    );
  }

  Widget _buildNewButton() {
    return Card(
      child: InkWell(
        onTap: _newPainting,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              const Text('新建画', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectCard(ProjectMeta meta) {
    final thumb = _thumbs[meta.id];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openProject(meta),
        child: Stack(
          fit: StackFit.expand,
          children: [
            thumb != null
                ? RawImage(image: thumb, fit: BoxFit.cover)
                : Container(color: Colors.grey.shade200),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      meta.name,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${meta.modifiedAt.month}/${meta.modifiedAt.day} ${meta.modifiedAt.hour}:${meta.modifiedAt.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white70, size: 20),
                onPressed: () => _confirmDelete(meta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
