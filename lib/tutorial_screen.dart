import 'package:flutter/material.dart';

/// Tutorial page: brushes, layers, gestures guide.
class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使用教程')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(context, '笔刷', Icons.brush, [
            '• 底部笔刷栏左右滑动选择 18 种笔刷',
            '• 拖动滑块调整笔刷大小 (1-60)',
            '• 水彩/油画/粉笔/炭笔模拟真实材质',
            '• 发光/星云/星光适合梦幻效果',
            '• 毛笔有粗细变化，马克笔有三档粗细',
          ]),
          _section(context, '图层', Icons.layers, [
            '• 点击图层按钮打开图层面板',
            '• 新建/删除/排序图层',
            '• 每层可单独调整透明度和可见性',
            '• 导入图片会作为新图层叠加',
          ]),
          _section(context, '手势操作', Icons.pan_tool, [
            '• 单指拖动 = 绘画',
            '• 双指捏合 = 缩放画布',
            '• 双指拖动 = 平移画布',
            '• 双击 = 适应屏幕',
          ]),
          _section(context, '矢量工具', Icons.straighten, [
            '• 工具栏切换直线/矩形/圆/椭圆',
            '• 按住拖动画出形状，松手确认',
          ]),
          _section(context, '文字工具', Icons.text_fields, [
            '• 选文字工具后输入文字',
            '• 点击画布放置文字',
            '• 颜色和大小可调',
          ]),
          _section(context, '步骤回放', Icons.history, [
            '• 自动记录每一步绘画',
            '• 长按撤销按钮查看步骤时间轴',
            '• 拖动滑块回放绘画过程',
          ]),
          _section(context, '导出与保存', Icons.save_alt, [
            '• 工程自动保存为 .bin 格式',
            '• 导出 PNG/JPG 到 Download/Pcitrue 文件夹',
            '• 可导出 .bin 工程文件备份',
            '• 在手机文件管理器中可直接看到',
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, IconData icon, List<String> lines) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            ...lines.map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(l, style: const TextStyle(fontSize: 14, height: 1.4)),
                )),
          ],
        ),
      ),
    );
  }
}
