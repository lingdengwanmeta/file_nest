import 'package:flutter/material.dart';

/// 依据扩展名判定的文件类别，用于选择图标与预览方式。
enum FileKind { image, text, pdf, audio, video, archive, other }

const _imageExt = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif'};
const _textExt = {
  'txt', 'md', 'markdown', 'json', 'xml', 'yaml', 'yml', 'csv', 'log',
  'ini', 'conf', 'html', 'htm', 'css', 'js', 'ts', 'dart', 'py', 'java',
  'kt', 'c', 'cpp', 'h', 'cs', 'go', 'rs', 'sql', 'sh', 'bat', 'ps1',
};
const _audioExt = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'ape'};
const _videoExt = {'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', '3gp'};
const _archiveExt = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso'};

String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

FileKind kindOf(String name) {
  final ext = extensionOf(name);
  if (_imageExt.contains(ext)) return FileKind.image;
  if (_textExt.contains(ext)) return FileKind.text;
  if (ext == 'pdf') return FileKind.pdf;
  if (_audioExt.contains(ext)) return FileKind.audio;
  if (_videoExt.contains(ext)) return FileKind.video;
  if (_archiveExt.contains(ext)) return FileKind.archive;
  return FileKind.other;
}

IconData iconOf(FileKind kind) {
  switch (kind) {
    case FileKind.image:
      return Icons.image_outlined;
    case FileKind.text:
      return Icons.description_outlined;
    case FileKind.pdf:
      return Icons.picture_as_pdf_outlined;
    case FileKind.audio:
      return Icons.audiotrack_outlined;
    case FileKind.video:
      return Icons.movie_outlined;
    case FileKind.archive:
      return Icons.folder_zip_outlined;
    case FileKind.other:
      return Icons.insert_drive_file_outlined;
  }
}

Color colorOf(FileKind kind, ColorScheme scheme) {
  switch (kind) {
    case FileKind.image:
      return const Color(0xFF2FB27C);
    case FileKind.text:
      return const Color(0xFF3D7DE0);
    case FileKind.pdf:
      return const Color(0xFFE05146);
    case FileKind.audio:
      return const Color(0xFF8A5CF6);
    case FileKind.video:
      return const Color(0xFFE08A2B);
    case FileKind.archive:
      return const Color(0xFF6B7B8C);
    case FileKind.other:
      return scheme.outline;
  }
}
