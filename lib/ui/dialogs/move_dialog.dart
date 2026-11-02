import 'package:flutter/material.dart';

import '../../data/models.dart';

/// 移动目标（[parentId] 为 null 表示根目录）。
class MoveTarget {
  const MoveTarget(this.parentId, this.label);

  final int? parentId;
  final String label;
}

/// 打开目录选择器；[blockedRoots] 中的节点及其所有后代不可作为目标。
Future<MoveTarget?> showMoveTargetPicker(
  BuildContext context, {
  required List<Node> folders,
  required Set<int> blockedRoots,
}) {
  return Navigator.of(context).push<MoveTarget>(
    MaterialPageRoute<MoveTarget>(
      builder: (_) => _MoveTargetPage(folders: folders, blockedRoots: blockedRoots),
    ),
  );
}

class _MoveTargetPage extends StatefulWidget {
  const _MoveTargetPage({required this.folders, required this.blockedRoots});

  final List<Node> folders;
  final Set<int> blockedRoots;

  @override
  State<_MoveTargetPage> createState() => _MoveTargetPageState();
}

class _MoveTargetPageState extends State<_MoveTargetPage> {
  final Map<int?, List<Node>> _childrenMap = <int?, List<Node>>{};
  final Set<int> _expanded = <int>{};
  final Set<int> _blocked = <int>{};

  int? _selected;
  String _selectedLabel = '根目录';

  @override
  void initState() {
    super.initState();
    for (final folder in widget.folders) {
      _childrenMap.putIfAbsent(folder.parentId, () => <Node>[]).add(folder);
    }
    for (final list in _childrenMap.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    for (final root in widget.blockedRoots) {
      _markBlocked(root);
    }
    for (final folder in _childrenMap[null] ?? const <Node>[]) {
      _expanded.add(folder.id);
    }
  }

  void _markBlocked(int id) {
    if (!_blocked.add(id)) return;
    for (final child in _childrenMap[id] ?? const <Node>[]) {
      _markBlocked(child.id);
    }
  }

  void _collectRows(int? parentId, int depth, List<Widget> out) {
    final items = _childrenMap[parentId] ?? const <Node>[];
    for (final node in items) {
      final hasChild = (_childrenMap[node.id] ?? const <Node>[]).isNotEmpty;
      final blocked = _blocked.contains(node.id);
      final selected = !blocked && _selected == node.id;
      final expanded = _expanded.contains(node.id);
      out.add(
        Material(
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : Colors.transparent,
          child: InkWell(
            onTap: blocked
                ? null
                : () => setState(() {
                      _selected = node.id;
                      _selectedLabel = node.name;
                    }),
            child: Padding(
              padding: EdgeInsets.only(left: 8.0 + depth * 18.0, right: 8),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: hasChild
                        ? InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() {
                              if (expanded) {
                                _expanded.remove(node.id);
                              } else {
                                _expanded.add(node.id);
                              }
                            }),
                            child: Icon(
                              expanded ? Icons.expand_more : Icons.chevron_right,
                              size: 20,
                            ),
                          )
                        : null,
                  ),
                  Icon(
                    blocked ? Icons.block : Icons.folder_outlined,
                    size: 20,
                    color: blocked
                        ? Theme.of(context).colorScheme.outline
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: blocked
                              ? Theme.of(context).colorScheme.outline
                              : null,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check, size: 20, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
          ),
        ),
      );
      if (expanded) _collectRows(node.id, depth + 1, out);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    _collectRows(null, 0, rows);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('移动到…')),
      body: ListView(
        children: <Widget>[
          Material(
            color: _selected == null
                ? theme.colorScheme.secondaryContainer
                : Colors.transparent,
            child: ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('根目录'),
              trailing: _selected == null ? const Icon(Icons.check) : null,
              onTap: () => setState(() {
                _selected = null;
                _selectedLabel = '根目录';
              }),
            ),
          ),
          const Divider(height: 1),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有子文件夹'),
            ),
          ...rows,
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('目标位置：$_selectedLabel',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('移动到此处'),
                  onPressed: () => Navigator.of(context)
                      .pop(MoveTarget(_selected, _selectedLabel)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
