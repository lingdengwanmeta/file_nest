# ============================================================
#  文件柜 (file_nest) 一键准备脚本
#  作用：生成 Android 平台工程（android/、gradle 等脚手架），
#        合入本目录已有的 lib 源码，配置应用名称，并拉取依赖。
#  用法：右键“使用 PowerShell 运行”，或在终端执行：
#        powershell -ExecutionPolicy Bypass -File .\setup.ps1
#  前置条件：已安装 Flutter SDK（bin 在 PATH 中）、JDK 17+、Git
# ============================================================

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Assert-Command([string]$name, [string]$hint) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "未找到命令 '$name'。$hint"
    }
}

Assert-Command 'flutter' '请先安装 Flutter SDK，把 <flutter>\bin 加入 PATH 后重新打开终端。'
Assert-Command 'java' '请安装 JDK 17 或更高版本并设置 JAVA_HOME。'

Write-Host '==> 检查 Flutter 环境' -ForegroundColor Cyan
flutter --version

$tmp = Join-Path $env:TEMP ('file_nest_scaffold_' + [guid]::NewGuid().ToString('N'))
try {
    Write-Host "==> 生成平台脚手架: $tmp" -ForegroundColor Cyan
    flutter create --org com.example --project-name file_nest --platforms android --empty $tmp
    if ($LASTEXITCODE -ne 0) { throw "flutter create 执行失败（exit $LASTEXITCODE）" }

    Write-Host '==> 合入 android / 工程配置文件（保留本目录的 lib 与 pubspec.yaml）' -ForegroundColor Cyan
    foreach ($item in @('android', '.gitignore', '.metadata', 'analysis_options.yaml')) {
        $src = Join-Path $tmp $item
        if (-not (Test-Path $src)) { continue }
        $dst = Join-Path $root $item
        if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
        Copy-Item $src $dst -Recurse -Force
    }
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---- 应用显示名称改为中文，并为 Android 11+ 补充 queries 声明 ----
$manifest = Join-Path $root 'android\app\src\main\AndroidManifest.xml'
if (Test-Path $manifest) {
    $text = [System.IO.File]::ReadAllText($manifest)
    $text = $text -replace 'android:label="file_nest"', 'android:label="文件柜"'
    if ($text -notmatch '<queries>') {
        $queries = @'
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:mimeType="*/*" />
        </intent>
    </queries>
</manifest>
'@
        $text = $text -replace '</manifest>', $queries
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($manifest, $text, $utf8)
    Write-Host '==> 已设置应用名称「文件柜」并补充 queries 声明' -ForegroundColor Cyan
}

Write-Host '==> flutter pub get' -ForegroundColor Cyan
Push-Location $root
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get 执行失败（exit $LASTEXITCODE）" }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host '准备完成，后续步骤：' -ForegroundColor Green
Write-Host '  1) 手机开启开发者选项 + USB 调试，连接电脑后运行: flutter devices'
Write-Host '  2) 直接调试运行: flutter run --release'
Write-Host '  3) 生成安装包:   flutter build apk --release'
Write-Host '  4) 安装包路径:   build\app\outputs\flutter-apk\app-release.apk'
Write-Host ''
