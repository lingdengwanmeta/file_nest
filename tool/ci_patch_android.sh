#!/usr/bin/env bash
# 在 CI 生成的 Android 工程上做最小改动：
#   1) 应用显示名称改为「文件柜」
#   2) 补充 Android 11+ 的 <queries> 声明，保证「用其他应用打开」可用
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ ! -f "$MANIFEST" ]; then
  echo "未找到 $MANIFEST，android 工程未生成？"
  exit 1
fi

python3 - "$MANIFEST" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as fh:
    text = fh.read()

text = text.replace('android:label="file_nest"', 'android:label="文件柜"')

if 'READ_MEDIA_IMAGES' not in text:
    permissions = (
        '    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />\n'
        '    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />\n'
        '    <uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" />\n'
        '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />\n'
    )
    text = text.replace('    <application', permissions + '    <application', 1)

if '<queries>' not in text:
    block = (
        '    <queries>\n'
        '        <intent>\n'
        '            <action android:name="android.intent.action.VIEW" />\n'
        '            <data android:mimeType="*/*" />\n'
        '        </intent>\n'
        '    </queries>\n'
        '</manifest>'
    )
    text = text.replace('</manifest>', block)

with open(path, 'w', encoding='utf-8') as fh:
    fh.write(text)

print('AndroidManifest 已更新')
PY
