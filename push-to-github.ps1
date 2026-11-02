# ============================================================
#  把本项目推送到 GitHub，触发云端构建 APK
#  用法：
#    powershell -ExecutionPolicy Bypass -File .\push-to-github.ps1 https://github.com/你的用户名/仓库名.git
#  前置：已安装 Git；已在 GitHub 网页新建一个空仓库（不要勾选 README / .gitignore）
# ============================================================

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RepoUrl,
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($RepoUrl -match '你的用户名|your-username|USERNAME') {
    throw '请先把 URL 中的“你的用户名”替换成你自己的 GitHub 用户名，例如 https://github.com/zhangsan/file_nest.git'
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw '未找到 git 命令，请先安装 Git for Windows。'
}

# 未配置提交身份时用环境变量兜底，不修改任何 git 配置
$email = git config user.email 2>$null
if ([string]::IsNullOrWhiteSpace($email)) {
    $env:GIT_AUTHOR_NAME = 'file_nest'
    $env:GIT_AUTHOR_EMAIL = 'file_nest@users.noreply.github.com'
    $env:GIT_COMMITTER_NAME = 'file_nest'
    $env:GIT_COMMITTER_EMAIL = 'file_nest@users.noreply.github.com'
}

Push-Location $root
try {
    if (-not (Test-Path (Join-Path $root '.git'))) {
        Write-Host '==> 初始化本地仓库' -ForegroundColor Cyan
        git init -b $Branch | Out-Null
    }

    git add -A
    git commit -m 'feat: 文件柜 - 本地无限级分类文件管理器' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '没有新的改动需要提交，继续推送。' -ForegroundColor Yellow
    }
    git branch -M $Branch

    $remotes = git remote
    if ($remotes -contains 'origin') {
        git remote set-url origin $RepoUrl
    }
    else {
        git remote add origin $RepoUrl
    }

    Write-Host "==> 推送到 $RepoUrl" -ForegroundColor Cyan
    Write-Host '首次推送会弹出浏览器要求登录 GitHub，授权后自动完成。' -ForegroundColor Yellow
    git push -u origin $Branch

    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host '推送失败。常见原因：' -ForegroundColor Red
        Write-Host '  1) 远程仓库不是空仓库（创建时勾了 README），改为新建空仓库后重试'
        Write-Host '  2) 没有登录 GitHub：再次执行会弹出登录窗口；也可用 Personal Access Token 作为密码'
        Write-Host '  3) 网络无法访问 github.com'
        exit 1
    }

    $webUrl = $RepoUrl -replace '\.git$', ''
    Write-Host ''
    Write-Host '推送完成。打开 Actions 页面查看构建：' -ForegroundColor Green
    Write-Host "  $webUrl/actions"
    Write-Host ''
    Write-Host '构建成功后，在该次运行页面底部 Artifacts 下载 file_nest-apk.zip，解压即得 app-release.apk。'
}
finally {
    Pop-Location
}
