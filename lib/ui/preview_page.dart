import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../data/file_store.dart';
import '../data/models.dart';
import '../utils/file_kind.dart';
import '../utils/formatters.dart';

/// 文件预览：图片直接渲染，文本内联显示，其余交给系统应用。
class PreviewPage extends StatelessWidget {
  const PreviewPage({super.key, required this.node});

  final Node node;

  Future<File> _resolve() => FileStore.instance.resolve(node.relPath ?? '');

  @override
  Widget build(BuildContext context) {
    final kind = kindOf(node.name);
    final isImage = kind == FileKind.image;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isImage ? Colors.black : scheme.surface,
      appBar: AppBar(
        backgroundColor: isImage ? Colors.black : null,
        foregroundColor: isImage ? Colors.white : null,
        title: Text(
          node.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '用其他应用打开',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openExternal(context),
          ),
          IconButton(
            tooltip: '详情',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfo(context, kind),
          ),
        ],
      ),
      body: FutureBuilder<File>(
        future: _resolve(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final file = snapshot.data;
          if (file == null || !file.existsSync()) {
            return _missing(context);
          }
          switch (kind) {
            case FileKind.image:
              return _imageView(file);
            case FileKind.text:
              return _textView(context, file);
            case FileKind.pdf:
            case FileKind.audio:
            case FileKind.video:
            case FileKind.archive:
            case FileKind.other:
              return _fallback(context, file, kind);
          }
        },
      ),
    );
  }

  Widget _imageView(File file) {
    return Center(
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 6,
        child: Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => const Padding(
            padding: EdgeInsets.all(24),
            child: Text('图片无法解码', style: TextStyle(color: Colors.white70)),
          ),
        ),
      ),
    );
  }

  Widget _textView(BuildContext context, File file) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<String>(
      future: _readText(file),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('读取失败：${snapshot.error}'));
        }
        return Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              snapshot.data ?? '',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.55,
                color: scheme.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String> _readText(File file) async {
    const limit = 256 * 1024;
    final raf = await file.open();
    try {
      final length = await raf.length();
      final bytes = await raf.read(length > limit ? limit : length);
      final text = utf8.decode(bytes, allowMalformed: true);
      return length > limit ? '$text\n\n—— 仅显示前 256 KB ——' : text;
    } finally {
      await raf.close();
    }
  }

  Widget _fallback(BuildContext context, File file, FileKind kind) {
    final scheme = Theme.of(context).colorScheme;
    final color = colorOf(kind, scheme);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(iconOf(kind), size: 46, color: color),
            ),
            const SizedBox(height: 20),
            Text(
              node.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatSize(node.size)} · ${formatDateTime(node.updatedAt)}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('用其他应用打开'),
              onPressed: () => _openExternal(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _missing(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            const Text('文件实体已丢失'),
            const SizedBox(height: 8),
            Text(
              '可能被系统清理或应用数据被改动',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternal(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await _resolve();
    if (!file.existsSync()) {
      messenger.showSnackBar(const SnackBar(content: Text('文件实体已丢失')));
      return;
    }
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      messenger.showSnackBar(
        SnackBar(content: Text('无法打开：${result.message}')),
      );
    }
  }

  Future<void> _showInfo(BuildContext context, FileKind kind) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('文件详情',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _infoRow('名称', node.name),
            _infoRow('类型', kind.name),
            _infoRow('大小', formatSize(node.size)),
            _infoRow('创建时间', formatDateTime(node.createdAt)),
            _infoRow('修改时间', formatDateTime(node.updatedAt)),
            _infoRow('存储位置', '应用私有目录/vault/${node.relPath ?? ''}'),
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
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
