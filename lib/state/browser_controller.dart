import 'package:flutter/foundation.dart';

import '../data/backup_state.dart';
import '../data/models.dart';
import '../data/node_repository.dart';

/// 当前浏览位置与列表状态。
///
/// [_path] 是从根到当前文件夹的完整链路，长度即层级深度，
/// 因此天然支持任意层级的嵌套。
class BrowserController extends ChangeNotifier {
  BrowserController(this._repo);

  final NodeRepository _repo;

  List<Node> _path = const <Node>[];
  List<Node> _items = const <Node>[];
  bool _loading = true;
  String? _error;
  SortField _sortField = SortField.name;
  bool _ascending = true;
  bool _gridMode = false;

  List<Node> get path => List<Node>.unmodifiable(_path);
  List<Node> get items => List<Node>.unmodifiable(_items);
  bool get loading => _loading;
  String? get error => _error;
  int? get currentFolderId => _path.isEmpty ? null : _path.last.id;
  String get currentTitle => _path.isEmpty ? '文件柜' : _path.last.name;
  SortField get sortField => _sortField;
  bool get ascending => _ascending;
  bool get gridMode => _gridMode;
  bool get canGoUp => _path.isNotEmpty;
  int get depth => _path.length;

  Future<void> init() => load();

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _repo.children(
        parentId: currentFolderId,
        field: _sortField,
        ascending: _ascending,
      );
    } catch (error) {
      _error = '读取目录失败：$error';
      _items = const <Node>[];
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> enter(Node folder) async {
    if (!folder.isFolder) return;
    _path = <Node>[..._path, folder];
    await load();
  }

  Future<void> goUp() async {
    if (_path.isEmpty) return;
    _path = _path.sublist(0, _path.length - 1);
    await load();
  }

  Future<void> jumpToDepth(int depth) async {
    final target = depth.clamp(0, _path.length);
    _path = _path.sublist(0, target);
    await load();
  }

  /// 直接跳转到一条完整路径（搜索结果定位用）。
  Future<void> jumpToPath(List<Node> path) async {
    _path = List<Node>.of(path);
    await load();
  }

  /// 跳转到某个节点所在目录（搜索结果定位用）。
  Future<void> revealNode(Node node) async {
    _path = await _repo.ancestorsOf(node.parentId);
    await load();
  }

  /// 当前目录被重命名/移动后，重建路径名称。
  Future<void> refreshPath() async {
    if (_path.isEmpty) return;
    _path = await _repo.ancestorsOf(_path.last.id);
    notifyListeners();
  }

  Future<void> setSort(SortField field, {bool? ascending}) async {
    _sortField = field;
    if (ascending != null) _ascending = ascending;
    await load();
  }

  Future<void> toggleAscending() => setSort(_sortField, ascending: !_ascending);

  void setGridMode(bool value) {
    if (_gridMode == value) return;
    _gridMode = value;
    notifyListeners();
  }

  // -------------------------------------------------------------- 写操作

  Future<Node> createFolder(String name) async {
    final node = await _repo.createFolder(name: name, parentId: currentFolderId);
    await BackupState.instance.markDirty();
    await load();
    return node;
  }

  Future<List<Node>> importFiles(
    List<ImportSource> sources, {
    void Function(int done, int total)? onProgress,
  }) async {
    final created = await _repo.importFiles(
      sources: sources,
      parentId: currentFolderId,
      onProgress: onProgress,
    );
    await BackupState.instance.markDirty();
    await load();
    return created;
  }

  Future<void> rename(Node node, String newName) async {
    await _repo.rename(node.id, newName);
    await BackupState.instance.markDirty();
    await load();
    if (!node.isFolder) return;
    final isOnPath = _path.any((item) => item.id == node.id);
    if (isOnPath) await refreshPath();
  }

  Future<void> moveNodes(List<Node> nodes, int? targetParentId) async {
    await _repo.move(
      ids: nodes.map((node) => node.id).toList(),
      targetParentId: targetParentId,
    );
    await BackupState.instance.markDirty();
    await load();
    final ids = nodes.map((node) => node.id).toSet();
    if (_path.any((item) => ids.contains(item.id))) {
      _path = const <Node>[];
      await load();
    }
  }

  Future<void> deleteNodes(List<Node> nodes) async {
    await _repo.deleteMany(nodes.map((node) => node.id).toList());
    await BackupState.instance.markDirty();
    await load();
    final ids = nodes.map((node) => node.id).toSet();
    if (_path.any((item) => ids.contains(item.id))) {
      _path = const <Node>[];
      await load();
    }
  }

  Future<({int folders, int files, int bytes})> currentStats() =>
      _repo.stats(currentFolderId);
}
