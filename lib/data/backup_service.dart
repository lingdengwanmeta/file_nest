import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'backup_state.dart';
import 'file_store.dart';
import 'models.dart';

class BackupResult {
  const BackupResult({
    required this.file,
    required this.fileCount,
    required this.totalBytes,
  });

  final File file;
  final int fileCount;
  final int totalBytes;
}

/// 整库备份与恢复：把数据库与 vault 内全部文件打包成一个 zip。
///
/// 备份包结构：
/// ```
/// database/file_nest.db
/// vault/<与 App 内记录一致的相对路径>
/// ```
/// 因为记录的是相对路径，整包搬到新设备后可直接还原，无需改路径。
///
/// 自动备份写到外部专属目录（Android/data/<包名>/files/backups/），
/// 无需任何存储权限，连电脑即可拷走；但卸载 App 时会被系统一并删除。
class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const String dbEntryDir = 'database';
  static const String vaultEntryDir = 'vault';
  static const String backupPrefix = 'file_nest_backup_';
  static const String autoBackupFileName = 'file_nest_backup_latest.zip';

  bool _running = false;

  bool get isRunning => _running;

  /// 自动备份目录；无法获取外部目录时返回 null。
  Future<Directory?> autoBackupDirectory() async {
    try {
      final external = await getExternalStorageDirectory();
      if (external == null) return null;
      final dir = Directory(p.join(external.path, 'backups'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// 手动备份：生成到临时目录，供分享或导出。
  Future<BackupResult> createBackup({
    void Function(String message)? onProgress,
  }) async {
    if (_running) {
      throw NodeOpException('正在备份中，请稍后再试');
    }
    final tempRoot = await getTemporaryDirectory();
    final workDir = Directory(p.join(tempRoot.path, 'backup'));
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
    await workDir.create(recursive: true);
    final zipFile = File(p.join(workDir.path, '$backupPrefix${_stamp()}.zip'));
    _running = true;
    try {
      return await _writeBackup(zipFile, onProgress: onProgress);
    } finally {
      _running = false;
    }
  }

  /// 自动备份：只保留最新一份，仅在 [force] 或存在未备份改动时执行。
  Future<BackupResult?> autoBackup({
    bool force = false,
    void Function(String message)? onProgress,
  }) async {
    if (_running) return null;
    await BackupState.instance.load();
    final state = BackupState.instance;
    if (!force && !state.dirty && !state.pending) return null;

    final dir = await autoBackupDirectory();
    if (dir == null) return null;

    _running = true;
    final target = File(p.join(dir.path, autoBackupFileName));
    final temp = File('${target.path}.tmp');
    try {
      await state.markPending();
      if (await temp.exists()) await temp.delete();
      final result = await _writeBackup(temp, onProgress: onProgress);
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
      await state.markDone(
        fileCount: result.fileCount,
        bytes: result.totalBytes,
        path: target.path,
      );
      return BackupResult(
        file: target,
        fileCount: result.fileCount,
        totalBytes: result.totalBytes,
      );
    } catch (_) {
      // 保留 pending 标记，下次启动补做
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      rethrow;
    } finally {
      _running = false;
    }
  }

  /// 用备份包覆盖当前全部数据。
  Future<void> restore(
    File zipFile, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('正在解压备份包…');
    await AppDatabase.instance.close();

    final tempRoot = await getTemporaryDirectory();
    final workDir = Directory(
      p.join(tempRoot.path, 'restore_${DateTime.now().millisecondsSinceEpoch}'),
    );
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
    await workDir.create(recursive: true);

    try {
      await extractFileToDisk(zipFile.path, workDir.path);

      final srcDb = File(p.join(workDir.path, dbEntryDir, AppDatabase.dbName));
      final srcVault = Directory(p.join(workDir.path, vaultEntryDir));
      if (!await srcDb.exists()) {
        throw NodeOpException('备份包不完整：缺少数据库文件');
      }

      onProgress?.call('正在恢复分类与记录…');
      final dbDir = await getDatabasesPath();
      await Directory(dbDir).create(recursive: true);
      for (final suffix in <String>['', '-wal', '-shm']) {
        final stale = File(p.join(dbDir, '${AppDatabase.dbName}$suffix'));
        if (await stale.exists()) await stale.delete();
      }
      await srcDb.copy(p.join(dbDir, AppDatabase.dbName));

      onProgress?.call('正在恢复文件…');
      final vault = await FileStore.instance.root();
      if (await vault.exists()) {
        await vault.delete(recursive: true);
      }
      await vault.create(recursive: true);
      if (await srcVault.exists()) {
        await _copyDirectory(srcVault, vault);
      }

      await BackupState.instance.load();
      await BackupState.instance.markDirty();
    } finally {
      await AppDatabase.instance.database;
      try {
        if (await workDir.exists()) await workDir.delete(recursive: true);
      } catch (_) {
        // 临时目录清理失败不影响恢复结果
      }
    }
  }

  Future<BackupResult> _writeBackup(
    File zipFile, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('正在关闭数据库…');
    // 先断开连接，保证复制出来的 .db 是一致的
    await AppDatabase.instance.close();

    final dbFile = File(p.join(await getDatabasesPath(), AppDatabase.dbName));
    final vault = await FileStore.instance.root();

    var fileCount = 0;
    var totalBytes = 0;

    final encoder = ZipFileEncoder();
    encoder.create(zipFile.path);
    try {
      if (await dbFile.exists()) {
        await encoder.addFile(dbFile, '$dbEntryDir/${AppDatabase.dbName}');
        totalBytes += await dbFile.length();
      }

      onProgress?.call('正在打包文件…');
      if (await vault.exists()) {
        await for (final entity
            in vault.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final rel = p.relative(entity.path, from: vault.path);
          final normalized = rel.replaceAll(r'\', '/');
          await encoder.addFile(entity, '$vaultEntryDir/$normalized');
          fileCount++;
          totalBytes += await entity.length();
        }
      }
    } finally {
      await encoder.close();
      // 备份结束立即恢复可用状态
      await AppDatabase.instance.database;
    }

    return BackupResult(
      file: zipFile,
      fileCount: fileCount,
      totalBytes: totalBytes,
    );
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is File) {
        await entity.copy(p.join(target.path, name));
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(p.join(target.path, name)));
      }
    }
  }

  String _stamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
