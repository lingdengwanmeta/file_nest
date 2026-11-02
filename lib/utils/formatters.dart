/// 文件大小与时间的展示格式化。
String formatSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final text = unit == 0 || size >= 100
      ? size.toStringAsFixed(0)
      : size.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String formatTime(int millis) {
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  final sameDay = now.year == time.year && now.month == time.month && now.day == time.day;
  if (sameDay) return '今天 ${_two(time.hour)}:${_two(time.minute)}';
  final yesterday = now.subtract(const Duration(days: 1));
  if (yesterday.year == time.year &&
      yesterday.month == time.month &&
      yesterday.day == time.day) {
    return '昨天 ${_two(time.hour)}:${_two(time.minute)}';
  }
  if (now.year == time.year) return '${time.month}月${time.day}日';
  return '${time.year}-${_two(time.month)}-${_two(time.day)}';
}

String formatDateTime(int millis) {
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${time.year}-${_two(time.month)}-${_two(time.day)} '
      '${_two(time.hour)}:${_two(time.minute)}';
}
