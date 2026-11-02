import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import '../data/models.dart';

/// App 内相册页：按相册浏览手机中的图片与视频，多选后返回待导入文件列表。
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, required this.targetName});

  /// 目标分类名称，仅用于界面提示。
  final String targetName;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  static const int _pageSize = 60;

  final ScrollController _scrollController = ScrollController();
  final List<AssetEntity> _assets = <AssetEntity>[];
  final List<AssetEntity> _selected = <AssetEntity>[];

  List<AssetPathEntity> _albums = const <AssetPathEntity>[];
  AssetPathEntity? _album;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _denied = false;
  bool _preparing = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _init() async {
    final PermissionState state = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    if (!state.hasAccess) {
      setState(() {
        _denied = true;
        _loading = false;
      });
      return;
    }
    final albums = await PhotoManager.getAssetPathList(type: RequestType.common);
    if (!mounted) return;
    if (albums.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _albums = albums;
      _album = albums.first;
    });
    await _reload();
  }

  Future<void> _reload() async {
    final album = _album;
    if (album == null) return;
    setState(() {
      _loading = true;
      _page = 0;
      _hasMore = true;
    });
    final list = await album.getAssetListPaged(page: 0, size: _pageSize);
    if (!mounted) return;
    setState(() {
      _assets
        ..clear()
        ..addAll(list);
      _loading = false;
      _hasMore = list.length >= _pageSize;
    });
  }

  Future<void> _loadMore() async {
    final album = _album;
    if (album == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final list = await album.getAssetListPaged(page: next, size: _pageSize);
    if (!mounted) return;
    setState(() {
      _page = next;
      _assets.addAll(list);
      _loadingMore = false;
      _hasMore = list.length >= _pageSize;
    });
  }

  int? _orderOf(AssetEntity asset) {
    final index = _selected.indexWhere((item) => item.id == asset.id);
    return index < 0 ? null : index + 1;
  }

  void _toggle(AssetEntity asset) {
    setState(() {
      final index = _selected.indexWhere((item) => item.id == asset.id);
      if (index >= 0) {
        _selected.removeAt(index);
      } else {
        _selected.add(asset);
      }
    });
  }

  Future<void> _pickAlbum() async {
    if (_albums.isEmpty) return;
    final picked = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _albums.length,
          itemBuilder: (context, index) {
            final album = _albums[index];
            final active = album.id == _album?.id;
            return ListTile(
              leading: Icon(
                active ? Icons.photo_album : Icons.photo_album_outlined,
                color: active ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(album.name ?? '相册'),
              trailing: active ? const Icon(Icons.check, size: 20) : null,
              onTap: () => Navigator.of(sheetContext).pop(album),
            );
          },
        ),
      ),
    );
    if (picked == null || picked.id == _album?.id) return;
    setState(() => _album = picked);
    await _reload();
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty || _preparing) return;
    setState(() => _preparing = true);
    final sources = <ImportSource>[];
    for (final asset in _selected) {
      try {
        final file = await asset.file;
        if (file == null) continue;
        var name = asset.title ?? '';
        if (name.isEmpty) name = p.basename(file.path);
        sources.add(
          ImportSource(
            path: file.path,
            name: name,
            size: await file.length(),
          ),
        );
      } catch (_) {
        // 单个资源读取失败时跳过，不影响其余文件
      }
    }
    if (!mounted) return;
    setState(() => _preparing = false);
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取所选内容，请检查权限')),
      );
      return;
    }
    Navigator.of(context).pop(sources);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: TextButton.icon(
          onPressed: _albums.isEmpty ? null : _pickAlbum,
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: Text(_album?.name ?? '相册'),
        ),
        actions: <Widget>[
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('清空'),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selected.isEmpty || _preparing ? null : _confirm,
              child: _preparing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('导入 ${_selected.length} 项到「${widget.targetName}」'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_denied) {
      return _hint(
        icon: Icons.lock_outline,
        title: '没有相册访问权限',
        message: '需要在系统设置中允许「文件柜」访问照片和视频',
        actionLabel: '去设置',
        onAction: PhotoManager.openSetting,
      );
    }
    if (_assets.isEmpty) {
      return _hint(
        icon: Icons.photo_outlined,
        title: '这个相册里没有照片或视频',
        message: '换一个相册试试',
        actionLabel: '选择相册',
        onAction: _pickAlbum,
      );
    }
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _assets.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _assets.length) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final asset = _assets[index];
        return _AssetTile(
          asset: asset,
          order: _orderOf(asset),
          onTap: () => _toggle(asset),
        );
      },
    );
  }

  Widget _hint({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52, color: scheme.outlineVariant),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _AssetTile extends StatefulWidget {
  const _AssetTile({
    required this.asset,
    required this.order,
    required this.onTap,
  });

  final AssetEntity asset;
  final int? order;
  final VoidCallback onTap;

  @override
  State<_AssetTile> createState() => _AssetTileState();
}

class _AssetTileState extends State<_AssetTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.asset
        .thumbnailDataWithSize(const ThumbnailSize.square(300));
    if (!mounted) return;
    setState(() => _thumb = data);
  }

  String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.order != null;
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_thumb != null)
            Image.memory(_thumb!, fit: BoxFit.cover, gaplessPlayback: true)
          else
            ColoredBox(color: scheme.surfaceContainerHighest),
          if (widget.asset.type == AssetType.video)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.videocam, size: 11, color: Colors.white),
                    const SizedBox(width: 2),
                    Text(
                      _duration(widget.asset.duration),
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          if (selected)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary, width: 3),
                color: scheme.primary.withValues(alpha: 0.18),
              ),
            ),
          Positioned(
            top: 5,
            right: 5,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? scheme.primary : Colors.black26,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: selected
                  ? Text(
                      '${widget.order}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimary,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
