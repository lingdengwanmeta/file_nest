/// 节点类型：文件夹 / 文件。
enum NodeKind {
  folder,
  file;

  static NodeKind fromDb(String value) =>
      value == 'folder' ? NodeKind.folder : NodeKind.file;

  String get asDb => name;
}

/// 分类树中的一个节点（无限层级，通过 parentId 构成邻接表）。
class Node {
  const Node({
    required this.id,
    required this.parentId,
    required this.name,
    required this.kind,
    required this.relPath,
    required this.size,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int? parentId;
  final String name;
  final NodeKind kind;

  /// 文件在应用私有目录中的相对路径（仅文件节点有值）。
  final String? relPath;
  final int size;
  final int createdAt;
  final int updatedAt;

  bool get isFolder => kind == NodeKind.folder;

  factory Node.fromMap(Map<String, Object?> map) => Node(
        id: map['id'] as int,
        parentId: map['parent_id'] as int?,
        name: map['name'] as String,
        kind: NodeKind.fromDb(map['kind'] as String),
        relPath: map['rel_path'] as String?,
        size: (map['size'] as int?) ?? 0,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );

  @override
  String toString() => 'Node($id, $name, ${kind.name})';
}

/// 待导入的外部文件描述。
class ImportSource {
  const ImportSource({required this.path, required this.name, required this.size});

  final String path;
  final String name;
  final int size;
}

/// 移动/重名等业务校验失败时抛出，携带可直接展示给用户的原因。
class NodeOpException implements Exception {
  NodeOpException(this.message);

  final String message;

  @override
  String toString() => message;
}
