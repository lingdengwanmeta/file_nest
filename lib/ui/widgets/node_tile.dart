import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../utils/file_kind.dart';
import '../../utils/formatters.dart';

enum NodeAction { rename, move, share, info, delete }

class _NodeVisual {
  const _NodeVisual(this.icon, this.color);

  final IconData icon;
  final Color color;

  static _NodeVisual of(Node node, ColorScheme scheme) {
    if (node.isFolder) {
      return _NodeVisual(Icons.folder_rounded, const Color(0xFFF0B429));
    }
    final kind = kindOf(node.name);
    return _NodeVisual(iconOf(kind), colorOf(kind, scheme));
  }
}

PopupMenuButton<NodeAction> _menuButton(
  BuildContext context,
  ValueChanged<NodeAction> onAction,
) {
  final scheme = Theme.of(context).colorScheme;

  PopupMenuItem<NodeAction> item(
    NodeAction value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final color = danger ? scheme.error : null;
    return PopupMenuItem<NodeAction>(
      value: value,
      height: 44,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  return PopupMenuButton<NodeAction>(
    icon: const Icon(Icons.more_vert),
    iconSize: 20,
    padding: EdgeInsets.zero,
    onSelected: onAction,
    itemBuilder: (context) => <PopupMenuEntry<NodeAction>>[
      item(NodeAction.rename, Icons.drive_file_rename_outline, '重命名'),
      item(NodeAction.move, Icons.drive_file_move_outline, '移动'),
      item(NodeAction.share, Icons.ios_share, '分享 / 导出'),
      item(NodeAction.info, Icons.info_outline, '详情'),
      item(NodeAction.delete, Icons.delete_outline, '删除', danger: true),
    ],
  );
}

Widget _selectionMark(bool selected, ColorScheme scheme) {
  return Icon(
    selected ? Icons.check_circle : Icons.radio_button_unchecked,
    size: 22,
    color: selected ? scheme.primary : scheme.outline,
  );
}

class NodeListTile extends StatelessWidget {
  const NodeListTile({
    super.key,
    required this.node,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
    this.selected = false,
    this.selecting = false,
  });

  final Node node;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<NodeAction> onAction;
  final bool selected;
  final bool selecting;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = _NodeVisual.of(node, scheme);
    final subtitle = node.isFolder
        ? '文件夹 · ${formatTime(node.updatedAt)}'
        : '${formatSize(node.size)} · ${formatTime(node.updatedAt)}';

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: visual.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(visual.icon, color: visual.color, size: 24),
      ),
      title: Text(
        node.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
      trailing: selecting
          ? _selectionMark(selected, scheme)
          : _menuButton(context, onAction),
    );
  }
}

class NodeGridCard extends StatelessWidget {
  const NodeGridCard({
    super.key,
    required this.node,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
    this.selected = false,
    this.selecting = false,
  });

  final Node node;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<NodeAction> onAction;
  final bool selected;
  final bool selecting;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = _NodeVisual.of(node, scheme);
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected
            ? BorderSide(color: scheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(visual.icon, color: visual.color, size: 22),
                  ),
                  const Spacer(),
                  if (selecting)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _selectionMark(selected, scheme),
                    )
                  else
                    _menuButton(context, onAction),
                ],
              ),
              const Spacer(),
              Text(
                node.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500, height: 1.25),
              ),
              const SizedBox(height: 4),
              Text(
                node.isFolder ? '文件夹' : formatSize(node.size),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
