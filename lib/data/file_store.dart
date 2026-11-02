import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 文件实体仓库：所有导入的文件都复制进应用私有目录 `vault/`，
/// 因此不依赖外部存储权限，也不会因原文件被移动/删除而失效。
class FileStore {
  FileStore._();

  static final FileStore instance = FileStore._();

  Directory? _rootDir;

  Future<Directory> root() async {
    final cached = _rootDir;
    if (cached != null) return cached;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'vault'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _rootDir = dir;
    return dir;
  }

  /// 把外部文件复制进 vault，返回相对路径。
  Future<String> saveFile(String sourcePath, String originalName) async {
    final dir = await root();
    final ext = p.extension(originalName);
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${_randomToken()}${ext.isEmpty ? '' : ext.toLowerCase()}';
    final target = File(p.join(dir.path, fileName));
    await File(sourcePath).copy(target.path);
    return fileName;
  }

  Future<File> resolve(String relPath) async {
    final dir = await root();
    return File(p.join(dir.path, relPath));
  }

  Future<bool> exists(String relPath) async {
    try {
      return await (await resolve(relPath)).exists();
    } catch (_) {
      return false;
    }
  }

  Future<int> sizeOf(String relPath) async {
    try {
      return await (await resolve(relPath)).length();
    } catch (_) {
      return 0;
    }
  }

  Future<void> delete(String relPath) async {
    try {
      final file = await resolve(relPath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 实体文件缺失时忽略，数据库记录仍会被清理。
    }
  }

  String _randomToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
