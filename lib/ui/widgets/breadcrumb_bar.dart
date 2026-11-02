import 'package:flutter/material.dart';

import '../../data/models.dart';

/// 可横向滚动的层级路径，点击任意一级可直接跳回。
class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({
    super.key,
    required this.path,
    required this.onSelect,
  });

  final List<Node> path;

  /// 参数为跳转层级：0 表示根目录，n 表示进入第 n 层。
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    final normalStyle = TextStyle(fontSize: 13, color: scheme.onSurfaceVariant);

    final children = <Widget>[
      InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onSelect(0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: <Widget>[
              Icon(Icons.home_outlined, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('文件柜', style: path.isEmpty ? activeStyle : normalStyle),
            ],
          ),
        ),
      ),
    ];

    for (var i = 0; i < path.length; i++) {
      final isLast = i == path.length - 1;
      children.add(
        Icon(Icons.chevron_right, size: 16, color: scheme.outlineVariant),
      );
      children.add(
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => onSelect(i + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              path[i].name,
              style: isLast ? activeStyle : normalStyle,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      color: scheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: children),
      ),
    );
  }
}
