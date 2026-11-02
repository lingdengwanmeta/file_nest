import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup_service.dart';
import '../data/backup_state.dart';
import '../data/file_store.dart';
import '../data/models.dart';
import '../data/node_repository.dart';
import '../state/browser_controller.dart';
import '../utils/file_kind.dart';
import '../utils/formatters.dart';
import 'backup_page.dart';
import 'dialogs/move_dialog.dart';
import 'dialogs/name_dialog.dart';
import 'gallery_page.dart';
import 'preview_page.dart';
import 'search_page.dart';
import 'widgets/breadcrumb_bar.dart';
import 'widgets/node_tile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final BrowserController _controller = BrowserController(NodeRepository.instance);

  bool _selecting = false;
  final Set<int> _selectedIds = <int>{};

  List<Node> get _selectedNodes => _controller.items
      .where((node) => _selectedIds.contains(node.id))
      .toList(growable: false);

  void _enterSelection(Node node) {
    setState(() {
      _selecting = true;
      _selectedIds
        ..clear()
        ..add(node.id);
    });
  }

  void _toggleSelection(Node node) {
    setState(() {
      if (!_selectedIds.remove(node.id)) {
        _selectedIds.add(node.id);
      }
    });
  }

  void _exitSelection() {
    if (!_selecting && _selectedIds.isEmpty) return;
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.init();
    unawaited(_resumePendingBackup());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android 无法监听真正的"退出"，用切到后台/离开界面作为离开信号。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_autoBackup());
    }
  }

  /// 上次备份被系统中断时，启动后补做。
  ///
  /// 要等首次列表加载完成再开始，否则备份过程中关闭数据库会打断查询。
  Future<void> _resumePendingBackup() async {
    await BackupState.instance.load();
    if (!BackupState.instance.pending && !BackupState.instance.dirty) return;
    var guard = 0;
    while (_controller.loading && guard < 60) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      guard++;
    }
    await _autoBackup();
  }

  Future<void> _autoBackup() async {
    if (!BackupState.instance.autoEnabled) return;
    if (BackupService.instance.isRunning) return;
    try {
      await BackupService.instance.autoBackup();
    } catch (_) {
      // 自动备份失败不打扰用户，pending 标记会让下次启动补做
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return PopScope(
          canPop: !_selecting && !_controller.canGoUp,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_selecting) {
              _exitSelection();
              return;
            }
            _controller.goUp();
          },
          child: Scaffold(
            appBar: _selecting
                ? _selectionAppBar()
                : AppBar(
              leading: _controller.canGoUp
                  ? IconButton(
                      tooltip: '上一级',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _controller.goUp,
                    )
                  : null,
              title: Text(
                _controller.currentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: <Widget>[
                IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.search),
                  onPressed: _openSearch,
                ),
                PopupMenuButton<String>(
                  tooltip: '排序',
                  icon: const Icon(Icons.sort),
                  onSelected: _onSortSelected,
                  itemBuilder: (context) => _sortItems(context),
                ),
                IconButton(
                  tooltip: _controller.gridMode ? '切换为列表' : '切换为网格',
                  icon: Icon(_controller.gridMode
                      ? Icons.view_list_outlined
                      : Icons.grid_view_outlined),
                  onPressed: () => _controller.setGridMode(!_controller.gridMode),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  icon: const Icon(Icons.more_vert),
                  onSelected: _onMoreSelected,
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'backup',
                      height: 44,
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.archive_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('备份与恢复', style: TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'about',
                      height: 44,
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.info_outline, size: 20),
                          SizedBox(width: 12),
                          Text('关于', style: TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              bottom: _controller.canGoUp
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(40),
                      child: BreadcrumbBar(
                        path: _controller.path,
                        onSelect: _controller.jumpToDepth,
                      ),
                    )
                  : null,
            ),
            floatingActionButton: _selecting
                ? null
                : FloatingActionButton.extended(
                    onPressed: _showCreateSheet,
                    icon: const Icon(Icons.add),
                    label: const Text('新建 / 导入'),
                  ),
            body: Column(
              children: <Widget>[
                Expanded(child: _buildBody()),
                _buildFooter(context),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ 批量选择

  AppBar _selectionAppBar() {
    final scheme = Theme.of(context).colorScheme;
    final count = _selectedIds.length;
    final total = _controller.items.length;
    final allSelected = total > 0 && count == total;

    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      bool danger = false,
    }) {
      final color = danger ? scheme.error : null;
      return PopupMenuItem<String>(
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

    return AppBar(
      leading: IconButton(
        tooltip: '退出选择',
        icon: const Icon(Icons.close),
        onPressed: _exitSelection,
      ),
      title: Text('已选 $count 项'),
      actions: <Widget>[
        IconButton(
          tooltip: allSelected ? '取消全选' : '全选',
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          onPressed: () => setState(() {
            if (allSelected) {
              _selectedIds.clear();
            } else {
              _selectedIds.addAll(_controller.items.map((node) => node.id));
            }
          }),
        ),
        PopupMenuButton<String>(
          tooltip: '批量操作',
          icon: const Icon(Icons.more_vert),
          enabled: count > 0,
          onSelected: _onSelectionAction,
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            item('move', Icons.drive_file_move_outline, '移动到…'),
            item('share', Icons.ios_share, '分享选中文件'),
            item('delete', Icons.delete_outline, '删除', danger: true),
          ],
        ),
      ],
    );
  }

  Future<void> _onSelectionAction(String value) async {
    final nodes = _selectedNodes;
    if (nodes.isEmpty) return;
    if (value == 'move') {
      await _moveNodes(nodes);
    } else if (value == 'share') {
      await _shareNodes(nodes);
    } else if (value == 'delete') {
      await _deleteNodes(nodes);
    }
  }

  Future<void> _moveNodes(List<Node> nodes) async {
    final folders = await NodeRepository.instance.allFolders();
    if (!mounted) return;
    final blocked = <int>{
      for (final node in nodes)
        if (node.isFolder) node.id,
    };
    final target = await showMoveTargetPicker(
      context,
      folders: folders,
      blockedRoots: blocked,
    );
    if (target == null) return;
    try {
      await _controller.moveNodes(nodes, target.parentId);
      _exitSelection();
      _snack('已移动 ${nodes.length} 项到「${target.label}」');
    } catch (error) {
      _snack('移动失败：$error');
    }
  }

  Future<void> _deleteNodes(List<Node> nodes) async {
    final hasFolder = nodes.any((node) => node.isFolder);
    final confirmed = await showConfirmDialog(
      context,
      title: nodes.length == 1 ? '删除' : '删除 ${nodes.length} 项',
      message: hasFolder
          ? '选中的文件夹会连同其中全部内容一起删除，且无法恢复。确定删除吗？'
          : '选中的文件将被删除，且无法恢复。确定删除吗？',
    );
    if (!confirmed) return;
    try {
      await _controller.deleteNodes(nodes);
      _exitSelection();
      _snack('已删除 ${nodes.length} 项');
    } catch (error) {
      _snack('删除失败：$error');
    }
  }

  Future<void> _shareNodes(List<Node> nodes) async {
    final files = <XFile>[];
    for (final node in nodes) {
      if (node.isFolder || node.relPath == null) continue;
      try {
        final entity = await FileStore.instance.resolve(node.relPath!);
        if (!await entity.exists()) continue;
        files.add(XFile(entity.path, name: node.name));
      } catch (_) {
        // 单个文件读取失败时跳过，不影响其余文件
      }
    }
    if (files.isEmpty) {
      _snack('选中的内容里没有可分享的文件');
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(files: files, subject: '来自文件柜'),
      );
      _exitSelection();
    } catch (error) {
      _snack('分享失败：$error');
    }
  }

  // ------------------------------------------------------------ 列表区域

  Widget _buildBody() {
    if (_controller.loading && _controller.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _controller.error;
    if (error != null) {
      return _MessageView(
        icon: Icons.error_outline,
        title: '无法读取目录',
        message: error,
        actionLabel: '重试',
        onAction: _controller.load,
      );
    }
    final items = _controller.items;
    if (items.isEmpty) {
      return _MessageView(
        icon: Icons.folder_open_outlined,
        title: '这里还没有内容',
        message: '新建一个子文件夹，或把手机中的文件导入进来',
        actionLabel: '新建文件夹',
        onAction: _createFolder,
        secondaryLabel: '导入文件',
        onSecondary: () => _pickFiles(imagesOnly: false),
      );
    }
    return RefreshIndicator(
      onRefresh: _controller.load,
      child: _controller.gridMode ? _buildGrid(items) : _buildList(items),
    );
  }

  Widget _buildList(List<Node> items) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final node = items[index];
        return NodeListTile(
          node: node,
          selected: _selectedIds.contains(node.id),
          selecting: _selecting,
          onTap: () => _selecting ? _toggleSelection(node) : _open(node),
          onLongPress: () =>
              _selecting ? _toggleSelection(node) : _enterSelection(node),
          onAction: (action) => _handleAction(node, action),
        );
      },
    );
  }

  Widget _buildGrid(List<Node> items) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 148,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final node = items[index];
        return NodeGridCard(
          node: node,
          selected: _selectedIds.contains(node.id),
          selecting: _selecting,
          onTap: () => _selecting ? _toggleSelection(node) : _open(node),
          onLongPress: () =>
              _selecting ? _toggleSelection(node) : _enterSelection(node),
          onAction: (action) => _handleAction(node, action),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _controller.items;
    final folders = items.where((node) => node.isFolder).length;
    final files = items.length - folders;
    var bytes = 0;
    for (final node in items) {
      if (!node.isFolder) bytes += node.size;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '$folders 个文件夹 · $files 个文件',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          if (bytes > 0)
            Text(
              formatSize(bytes),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 排序

  List<PopupMenuEntry<String>> _sortItems(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(String label, bool selected) => Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 10),
            Text(label),
          ],
        );

    return <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'name',
        child: row('按名称', _controller.sortField == SortField.name),
      ),
      PopupMenuItem<String>(
        value: 'time',
        child: row('按修改时间', _controller.sortField == SortField.updatedAt),
      ),
      PopupMenuItem<String>(
        value: 'size',
        child: row('按大小', _controller.sortField == SortField.size),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'order',
        child: row(_controller.ascending ? '当前：升序（改为降序）' : '当前：降序（改为升序）', false),
      ),
    ];
  }

  Future<void> _onSortSelected(String value) async {
    if (value == 'order') {
      await _controller.toggleAscending();
      return;
    }
    final field = switch (value) {
      'time' => SortField.updatedAt,
      'size' => SortField.size,
      _ => SortField.name,
    };
    await _controller.setSort(field);
  }

  // ------------------------------------------------------------ 交互动作

  void _open(Node node) {
    if (node.isFolder) {
      _exitSelection();
      _controller.enter(node);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PreviewPage(node: node)),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SearchPage(controller: _controller)),
    );
  }

  Future<void> _onMoreSelected(String value) async {
    if (value == 'backup') {
      await _openBackup();
    } else if (value == 'about') {
      await _showAbout();
    }
  }

  Future<void> _openBackup() async {
    final restored = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const BackupPage()),
    );
    if (restored == true) {
      await _controller.jumpToPath(const <Node>[]);
    }
  }

  Future<void> _pickFromGallery() async {
    final sources = await Navigator.of(context).push<List<ImportSource>>(
      MaterialPageRoute<List<ImportSource>>(
        builder: (_) => GalleryPage(targetName: _controller.currentTitle),
      ),
    );
    if (sources == null || sources.isEmpty) return;
    await _runImport(sources);
  }

  Future<void> _showAbout() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '文件柜 1.0.0',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              '本地离线的多级分类文件管理工具。所有数据只保存在本机应用私有目录，'
              '不联网、不上传、不需要账号。',
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '换机前请使用「备份与恢复」生成备份包，否则数据无法带走。',
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(Node node, NodeAction action) async {
    if (action == NodeAction.rename) {
      await _rename(node);
    } else if (action == NodeAction.move) {
      await _move(node);
    } else if (action == NodeAction.share) {
      await _shareNodes(<Node>[node]);
    } else if (action == NodeAction.delete) {
      await _delete(node);
    } else if (action == NodeAction.info) {
      await _showInfo(node);
    }
  }

  Future<void> _showCreateSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新建文件夹'),
              onTap: () => Navigator.of(sheetContext).pop('folder'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册导入'),
              subtitle: const Text('浏览手机中的图片与视频，可多选'),
              onTap: () => Navigator.of(sheetContext).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('导入文件'),
              subtitle: const Text('从手机中选择任意类型的文件'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (action == 'folder') {
      await _createFolder();
    } else if (action == 'gallery') {
      await _pickFromGallery();
    } else if (action == 'file') {
      await _pickFiles(imagesOnly: false);
    }
  }

  Future<void> _createFolder() async {
    final name = await showNameDialog(
      context,
      title: '新建文件夹',
      hint: '文件夹名称',
      confirmText: '创建',
    );
    if (name == null) return;
    try {
      await _controller.createFolder(name);
    } catch (error) {
      _snack('创建失败：$error');
    }
  }

  Future<void> _rename(Node node) async {
    final name = await showNameDialog(
      context,
      title: '重命名',
      initialValue: node.name,
      confirmText: '保存',
    );
    if (name == null) return;
    try {
      await _controller.rename(node, name);
    } catch (error) {
      _snack('重命名失败：$error');
    }
  }

  Future<void> _move(Node node) async {
    final folders = await NodeRepository.instance.allFolders();
    if (!mounted) return;
    final target = await showMoveTargetPicker(
      context,
      folders: folders,
      blockedRoots: node.isFolder ? <int>{node.id} : <int>{},
    );
    if (target == null) return;
    try {
      await _controller.moveNodes(<Node>[node], target.parentId);
      _snack('已移动到「${target.label}」');
    } catch (error) {
      _snack('移动失败：$error');
    }
  }

  Future<void> _delete(Node node) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除',
      message: node.isFolder
          ? '将删除「${node.name}」以及其中的全部子文件夹和文件，删除后无法恢复。'
          : '将删除「${node.name}」，删除后无法恢复。',
    );
    if (!confirmed) return;
    try {
      await _controller.deleteNodes(<Node>[node]);
      _snack('已删除「${node.name}」');
    } catch (error) {
      _snack('删除失败：$error');
    }
  }

  Future<void> _showInfo(Node node) async {
    final scheme = Theme.of(context).colorScheme;
    final kind = node.isFolder ? '文件夹' : kindOf(node.name).name;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  node.isFolder ? Icons.folder_rounded : iconOf(kindOf(node.name)),
                  color: node.isFolder
                      ? const Color(0xFFF0B429)
                      : colorOf(kindOf(node.name), scheme),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    node.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow('类型', kind),
            _infoRow('大小', node.isFolder ? '按内容合并计算' : formatSize(node.size)),
            _infoRow('层级深度', '${_controller.depth + 1} 级'),
            _infoRow('创建时间', formatDateTime(node.createdAt)),
            _infoRow('修改时间', formatDateTime(node.updatedAt)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 导入

  Future<void> _pickFiles({required bool imagesOnly}) async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: imagesOnly ? FileType.image : FileType.any,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final sources = <ImportSource>[];
      for (final file in result.files) {
        final path = file.path;
        if (path == null) continue;
        sources.add(ImportSource(path: path, name: file.name, size: file.size));
      }
      if (sources.isEmpty) {
        _snack('无法读取所选文件');
        return;
      }
      await _runImport(sources);
    } catch (error) {
      _snack('选择文件失败：$error');
    }
  }

  Future<void> _runImport(List<ImportSource> sources) async {
    final progress = ValueNotifier<int>(0);
    final navigator = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('正在导入'),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (context, done, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(
                  value: sources.isEmpty ? 0 : done / sources.length,
                ),
                const SizedBox(height: 14),
                Text('$done / ${sources.length}'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final created = await _controller.importFiles(
        sources,
        onProgress: (done, total) => progress.value = done,
      );
      if (mounted) navigator.pop();
      _snack('已导入 ${created.length} 个文件');
    } catch (error) {
      if (mounted) navigator.pop();
      _snack('导入失败：$error');
    } finally {
      progress.dispose();
    }
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (secondaryLabel != null) ...<Widget>[
                    OutlinedButton.icon(
                      onPressed: onSecondary,
                      icon: const Icon(Icons.file_upload_outlined, size: 18),
                      label: Text(secondaryLabel!),
                    ),
                    const SizedBox(width: 12),
                  ],
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(actionLabel!),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
