import 'package:flutter/material.dart';

/// 新建 / 重命名共用的单行输入弹窗。
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String hint = '名称',
  String confirmText = '确定',
}) {
  final controller = TextEditingController(text: initialValue);
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: initialValue.length,
  );

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      void submit() {
        final text = controller.text.trim();
        if (text.isEmpty) return;
        Navigator.of(dialogContext).pop(text);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (_) => submit(),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(onPressed: submit, child: Text(confirmText)),
        ],
      );
    },
  );
}

/// 危险操作确认弹窗。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '删除',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}
