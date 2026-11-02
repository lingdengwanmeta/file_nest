import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup_service.dart';
import '../data/backup_state.dart';
import '../utils/formatters.dart';
import 'dialogs/name_dialog.dart';

/// 备份与恢复：换机时用备份包整体迁移分类与文件。
///
/// 自动备份写到 Android/data/<包名>/files/backups/，只保留最新一份。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  String _status = '';
  bool _autoEnabled = true;
  int? _lastBackupAt;
  int? _lastFileCount;
  int? _lastBytes;
  String? _autoDirPath;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    await BackupState.instance.load();
    final dir = await BackupService.instance.autoBackupDirectory();
    if (!mounted) return;
    setState(() {
      _autoEnabled = BackupState.instance.autoEnabled;
      _lastBackupAt = BackupState.instance.lastBackupAt;
      _lastFileCount = BackupState.instance.lastFileCount;
      _lastBytes = BackupState.instance.lastBytes;
      _autoDirPath = dir?.path;
    });
  }

  Future<void> _toggleAuto(bool value) async {
    await BackupState.instance.setAutoEnabled(value);
    if (!mounted) return;
    setState(() => _autoEnabled = value);
  }

  Future<void> _autoBackupNow() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在生成自动备份…';
    });
    try {
      final result = await BackupService.instance.autoBackup(
        force: true,
        onProgress: (message) {
          if (mounted) setState(() => _status = message);
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = result == null
            ? '无法写入外部备份目录，请检查存储空间'
            : '自动备份完成：${result.fileCount} 个文件，'
                '约 ${formatSize(result.totalBytes)}';
      });
      await _loadState();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '自动备份失败：$error';
      });
    }
  }

  Future<void> _shareBackup() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '准备中…';
    });
    try {
      final result = await BackupService.instance.createBackup(
        onProgress: (message) {
          if (mounted) setState(() => _status = message);
        },
      );
      if (!mounted) return;
      setState(() => _status = '正在唤起分享…');
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(result.file.path, mimeType: 'application/zip'),
          ],
          subject: '文件柜备份',
          text: '文件柜完整备份（分类 + 文件），共 ${result.fileCount} 个文件，'
              '约 ${formatSize(result.totalBytes)}',
        ),
      );
      if (!mounted) return;
      setState(() {
        _status = '备份包已生成：${result.fileCount} 个文件，'
            '约 ${formatSize(result.totalBytes)}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '备份失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    final confirmed = await showConfirmDialog(
      context,
      title: '恢复备份',
      message: '将用备份包覆盖当前全部分类与文件，现有数据会被全部替换，且无法撤销。确定继续吗？',
      confirmText: '覆盖恢复',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _status = '准备恢复…';
    });
    try {
      await BackupService.instance.restore(
        File(path),
        onProgress: (message) {
          if (mounted) setState(() => _status = message);
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '恢复完成';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('备份已恢复，已回到根目录')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '恢复失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.info_outline, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    const Text(
                      '备份里有什么',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '一个 zip 文件，内含分类树（数据库）与你导入的全部文件本体。'
                  '换机后在新设备安装本 App，选择这个 zip 恢复，分类与文件都会原样回来。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: _autoEnabled,
            onChanged: _busy ? null : _toggleAuto,
            title: const Text('离开 App 时自动备份'),
            subtitle: const Text('数据有改动时才重新打包，只保留最新一份'),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _lastBackupAt == null
                      ? '还没有自动备份记录'
                      : '最近备份：${formatDateTime(_lastBackupAt!)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_lastBackupAt != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '${_lastFileCount ?? 0} 个文件 · 约 ${formatSize(_lastBytes ?? 0)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SelectableText(
                  _autoDirPath ?? '（当前设备无法获取外部目录）',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _autoBackupNow,
            icon: const Icon(Icons.save_outlined),
            label: const Text('立即生成自动备份'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _shareBackup,
            icon: const Icon(Icons.ios_share),
            label: const Text('生成备份包并分享到网盘'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore),
            label: const Text('从备份文件恢复'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          if (_busy) ...<Widget>[
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
          ],
          if (_status.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            SelectableText(
              _status,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: scheme.error),
                    const SizedBox(width: 8),
                    Text(
                      '换机前务必先导出',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '自动备份在应用专属目录里，卸载 App 时会被系统一起删除。'
                  '正确顺序：旧机生成备份 → 用数据线把 zip 拷到电脑 → 再卸载旧 App。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
