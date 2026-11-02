import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'file_store.dart';
import 'models.dart';

/// 列表排序字段。
enum SortField { name, updatedAt, size }

/// 分类树的所有读写逻辑。
class NodeRepository {
  NodeRepository._();

  static final NodeRepository instance = NodeRepository._();

  Future<Database> get _db => AppDatabase.instance.database;

  // ---------------------------------------------------------------- 查询

  Future<List<Node>> children({
    int? parentId,
    SortField field = SortField.name,
    bool ascending = true,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'nodes',
      where: parentId == null ? 'parent_id IS NULL' : 'parent_id = ?',
      whereArgs: parentId == null ? null : <Object?>[parentId],
    );
    final list = rows.map(Node.fromMap).toList();
    list.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      final cmp = switch (field) {
        SortField.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortField.updatedAt => a.updatedAt.compareTo(b.updatedAt),
        SortField.size => a.size.compareTo(b.size),
      };
      return ascending ? cmp : -cmp;
    });
    return list;
  }

  Future<Node?> findById(int id) async {
    final db = await _db;
    final rows =
        await db.query('nodes', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    if (rows.isEmpty) return null;
    return Node.fromMap(rows.first);
  }

  /// 返回从根到 [id] 的完整节点链（包含 [id] 自身）；[id] 为 null 时返回空列表。
  Future<List<Node>> ancestorsOf(int? id) async {
    final db = await _db;
    final chain = <Node>[];
    var cursor = id;
    var guard = 0;
    while (cursor != null && guard < 500) {
      final rows = await db.query(
        'nodes',
        where: 'id = ?',
        whereArgs: <Object?>[cursor],
        limit: 1,
      );
      if (rows.isEmpty) break;
      final node = Node.fromMap(rows.first);
      chain.insert(0, node);
      cursor = node.parentId;
      guard++;
    }
    return chain;
  }

  Future<bool> hasChildren(int id) async {
    final db = await _db;
    final rows = await db.query(
      'nodes',
      columns: <String>['id'],
      where: 'parent_id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<Node>> search(String keyword, {int limit = 200}) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return const <Node>[];
    final db = await _db;
    final escaped = trimmed
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final rows = await db.query(
      'nodes',
      where: "name LIKE ? ESCAPE '\\'",
      whereArgs: <Object?>['%$escaped%'],
      limit: limit,
    );
    final list = rows.map(Node.fromMap).toList();
    list.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  /// 所有文件夹（移动目标选择器使用）。
  Future<List<Node>> allFolders() async {
    final db = await _db;
    final rows = await db.query('nodes', where: "kind = 'folder'");
    final list = rows.map(Node.fromMap).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// 统计根目录下的文件夹/文件数量（首页概览用）。
  Future<({int folders, int files, int bytes})> stats(int? parentId) async {
    final db = await _db;
    final rows = await db.query(
      'nodes',
      where: parentId == null ? 'parent_id IS NULL' : 'parent_id = ?',
      whereArgs: parentId == null ? null : <Object?>[parentId],
    );
    var folders = 0;
    var files = 0;
    var bytes = 0;
    for (final row in rows) {
      final node = Node.fromMap(row);
      if (node.isFolder) {
        folders++;
      } else {
        files++;
        bytes += node.size;
      }
    }
    return (folders: folders, files: files, bytes: bytes);
  }

  // ---------------------------------------------------------------- 写入

  Future<Node> createFolder({required String name, int? parentId}) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final unique = await _uniqueName(db, parentId, name);
    final id = await db.insert('nodes', <String, Object?>{
      'parent_id': parentId,
      'name': unique,
      'kind': NodeKind.folder.asDb,
      'size': 0,
      'created_at': now,
      'updated_at': now,
    });
    final created = await findById(id);
    return created!;
  }

  /// 导入外部文件：先把实体复制进私有目录，再写入记录。
  Future<List<Node>> importFiles({
    required List<ImportSource> sources,
    int? parentId,
    void Function(int done, int total)? onProgress,
  }) async {
    final db = await _db;
    final created = <Node>[];
    var done = 0;
    for (final source in sources) {
      try {
        final relPath = await FileStore.instance.saveFile(source.path, source.name);
        final now = DateTime.now().millisecondsSinceEpoch;
        final unique = await _uniqueName(db, parentId, source.name);
        final size = await FileStore.instance.sizeOf(relPath);
        final id = await db.insert('nodes', <String, Object?>{
          'parent_id': parentId,
          'name': unique,
          'kind': NodeKind.file.asDb,
          'rel_path': relPath,
          'size': size,
          'created_at': now,
          'updated_at': now,
        });
        final node = await findById(id);
        if (node != null) created.add(node);
      } finally {
        done++;
        onProgress?.call(done, sources.length);
      }
    }
    return created;
  }

  Future<void> rename(int id, String newName) async {
    final db = await _db;
    final node = await findById(id);
    if (node == null) throw NodeOpException('节点已不存在');
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw NodeOpException('名称不能为空');
    if (trimmed == node.name) return;
    final unique = await _uniqueName(db, node.parentId, trimmed, excludeId: id);
    await db.update(
      'nodes',
      <String, Object?>{
        'name': unique,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 移动到新的父节点（[targetParentId] 为 null 表示根目录）。
  Future<void> move({required List<int> ids, required int? targetParentId}) async {
    final db = await _db;
    for (final id in ids) {
      if (id == targetParentId) {
        throw NodeOpException('不能移动到自身');
      }
      if (targetParentId != null && await _isDescendant(targetParentId, id)) {
        throw NodeOpException('不能移动到自己的子文件夹内');
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final id in ids) {
        final rows = await txn.query('nodes',
            columns: <String>['name'], where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
        if (rows.isEmpty) continue;
        final name = rows.first['name'] as String;
        final unique = await _uniqueName(txn, targetParentId, name, excludeId: id);
        await txn.update(
          'nodes',
          <String, Object?>{
            'parent_id': targetParentId,
            'name': unique,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
      }
    });
  }

  /// 删除节点；文件夹会连同整棵子树与磁盘文件一起删除。
  Future<void> deleteMany(List<int> ids) async {
    final db = await _db;
    final filePaths = <String>[];
    for (final id in ids) {
      await _collectFiles(db, id, filePaths);
      final rows = await db.query('nodes',
          columns: <String>['rel_path'], where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
      if (rows.isNotEmpty) {
        final rel = rows.first['rel_path'] as String?;
        if (rel != null) filePaths.add(rel);
      }
    }
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete('nodes', where: 'id = ?', whereArgs: <Object?>[id]);
      }
    });
    for (final rel in filePaths) {
      await FileStore.instance.delete(rel);
    }
  }

  /// 修复文件大小（例如外部文件被清理后，界面上可提示缺失）。
  Future<void> refreshSize(Node node) async {
    if (node.isFolder || node.relPath == null) return;
    final size = await FileStore.instance.sizeOf(node.relPath!);
    if (size == node.size) return;
    final db = await _db;
    await db.update('nodes', <String, Object?>{'size': size},
        where: 'id = ?', whereArgs: <Object?>[node.id]);
  }

  // ---------------------------------------------------------------- 内部工具

  Future<void> _collectFiles(DatabaseExecutor db, int id, List<String> out) async {
    final rows =
        await db.query('nodes', where: 'parent_id = ?', whereArgs: <Object?>[id]);
    for (final row in rows) {
      final node = Node.fromMap(row);
      if (node.isFolder) {
        await _collectFiles(db, node.id, out);
      } else if (node.relPath != null) {
        out.add(node.relPath!);
      }
    }
  }

  /// [candidateId] 是否是 [ancestorId] 的后代。
  Future<bool> _isDescendant(int candidateId, int ancestorId) async {
    final db = await _db;
    int? cursor = candidateId;
    var guard = 0;
    while (cursor != null && guard < 500) {
      if (cursor == ancestorId) return true;
      final rows = await db.query('nodes',
          columns: <String>['parent_id'],
          where: 'id = ?',
          whereArgs: <Object?>[cursor],
          limit: 1);
      if (rows.isEmpty) return false;
      cursor = rows.first['parent_id'] as int?;
      guard++;
    }
    return false;
  }

  /// 同一父节点下重名时自动追加 (1)、(2)…，保留扩展名。
  Future<String> _uniqueName(
    DatabaseExecutor db,
    int? parentId,
    String desired, {
    int? excludeId,
  }) async {
    final base = desired.trim().isEmpty ? '未命名' : desired.trim();
    final ext = p.extension(base);
    final stem = ext.isEmpty ? base : p.basenameWithoutExtension(base);
    var candidate = base;
    var index = 1;
    while (true) {
      final rows = await db.query(
        'nodes',
        columns: <String>['id'],
        where: parentId == null
            ? 'parent_id IS NULL AND name = ?'
            : 'parent_id = ? AND name = ?',
        whereArgs:
            parentId == null ? <Object?>[candidate] : <Object?>[parentId, candidate],
        limit: 1,
      );
      final conflict =
          rows.isNotEmpty && (excludeId == null || rows.first['id'] != excludeId);
      if (!conflict) return candidate;
      candidate = ext.isEmpty ? '$base ($index)' : '$stem ($index)$ext';
      index++;
      if (index > 9999) return candidate;
    }
  }
}
