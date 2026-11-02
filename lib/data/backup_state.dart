import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 自动备份状态：
/// - [dirty]   自上次成功备份后是否有数据变更
/// - [pending] 上次备份是否被系统中断（下次启动需要补做）
class BackupState {
  BackupState._();

  static final BackupState instance = BackupState._();

  bool dirty = false;
  bool pending = false;
  bool autoEnabled = true;
  int? lastBackupAt;
  int? lastFileCount;
  int? lastBytes;
  String? lastPath;

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _stateFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final map = Map<String, Object?>.from(jsonDecode(raw) as Map);
          dirty = map['dirty'] == true;
          pending = map['pending'] == true;
          autoEnabled = map['autoEnabled'] != false;
          lastBackupAt = map['lastBackupAt'] as int?;
          lastFileCount = map['lastFileCount'] as int?;
          lastBytes = map['lastBytes'] as int?;
          lastPath = map['lastPath'] as String?;
        }
      }
    } catch (_) {
      // 状态文件损坏时按全新状态处理
    }
    _loaded = true;
  }

  Future<void> markDirty() async {
    dirty = true;
    await _save();
  }

  Future<void> markPending() async {
    pending = true;
    await _save();
  }

  Future<void> setAutoEnabled(bool value) async {
    autoEnabled = value;
    await _save();
  }

  Future<void> markDone({
    required int fileCount,
    required int bytes,
    required String path,
  }) async {
    dirty = false;
    pending = false;
    lastBackupAt = DateTime.now().millisecondsSinceEpoch;
    lastFileCount = fileCount;
    lastBytes = bytes;
    lastPath = path;
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _stateFile();
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'dirty': dirty,
          'pending': pending,
          'autoEnabled': autoEnabled,
          'lastBackupAt': lastBackupAt,
          'lastFileCount': lastFileCount,
          'lastBytes': lastBytes,
          'lastPath': lastPath,
        }),
      );
    } catch (_) {
      // 状态写入失败不影响主流程
    }
  }

  Future<File> _stateFile() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'backup_state.json'));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }
}
