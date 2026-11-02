import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/node_repository.dart';
import '../state/browser_controller.dart';
import '../utils/file_kind.dart';
import '../utils/formatters.dart';
import 'preview_page.dart';

/// 全库按名称搜索，命中后可定位到所在层级。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.controller});

  final BrowserController controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _input = TextEditingController();
  final NodeRepository _repo = NodeRepository.instance;

  Timer? _debounce;
  List<Node> _results = const <Node>[];
  Map<int, Node> _folders = const <int, Node>{};
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _input.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    final folders = await _repo.allFolders();
    if (!mounted) return;
    setState(() {
      _folders = <int, Node>{for (final folder in folders) folder.id: folder};
    });
  }

  void _onChanged() {
    _debounce?.cancel();
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() => _results = const <Node>[]);
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      setState(() => _searching = true);
      final results = await _repo.search(text);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  String _pathOf(Node node) {
    final parts = <String>[];
    var parent = node.parentId;
    var guard = 0;
    while (parent != null && guard < 200) {
      final folder = _folders[parent];
      if (folder == null) break;
      parts.insert(0, folder.name);
      parent = folder.parentId;
      guard++;
    }
    return parts.isEmpty ? '文件柜' : '文件柜 / ${parts.join(' / ')}';
  }

  Future<void> _open(Node node) async {
    if (node.isFolder) {
      final path = await _repo.ancestorsOf(node.id);
      await widget.controller.jumpToPath(path);
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    await widget.controller.revealNode(node);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => PreviewPage(node: node)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _input,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索文件或文件夹名称',
            border: InputBorder.none,
          ),
        ),
        actions: <Widget>[
          if (_input.text.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.close),
              onPressed: _input.clear,
            ),
        ],
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.search_off,
                          size: 44, color: scheme.outlineVariant),
                      const SizedBox(height: 12),
                      Text(
                        _input.text.trim().isEmpty ? '输入关键字开始搜索' : '没有找到匹配项',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 64),
                  itemBuilder: (context, index) {
                    final node = _results[index];
                    final kind = kindOf(node.name);
                    return ListTile(
                      leading: Icon(
                        node.isFolder
                            ? Icons.folder_rounded
                            : iconOf(kind),
                        color: node.isFolder
                            ? const Color(0xFFF0B429)
                            : colorOf(kind, scheme),
                      ),
                      title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        _pathOf(node),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                      trailing: node.isFolder
                          ? null
                          : Text(
                              formatSize(node.size),
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                      onTap: () => _open(node),
                    );
                  },
                ),
    );
  }
}
