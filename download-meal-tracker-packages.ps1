# 食事管理アプリ パッケージ一括ダウンロードスクリプト
# 使い方: powershell -ExecutionPolicy Bypass -File download-meal-tracker-packages.ps1

param(
    [string]$urlsFile = "meal-tracker-all-packages.txt",
    [string]$downloadDir = "npm-packages"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Meal Tracker Package Downloader" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# URLファイルの存在確認
if (-not (Test-Path $urlsFile)) {
    Write-Host "Error: $urlsFile not found!" -ForegroundColor Red
    Write-Host "Please make sure meal-tracker-all-packages.txt is in the same directory." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This file should contain:" -ForegroundColor Yellow
    Write-Host "  - Basic Next.js packages (420)" -ForegroundColor White
    Write-Host "  - Prisma packages (4)" -ForegroundColor White
    Write-Host "  - Zustand packages (2)" -ForegroundColor White
    Write-Host "  - Recharts packages (15)" -ForegroundColor White
    Write-Host "  - bcryptjs packages (2)" -ForegroundColor White
    Write-Host "  Total: ~443 packages" -ForegroundColor White
    exit 1
}

# ダウンロードディレクトリを作成
if (-not (Test-Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir | Out-Null
    Write-Host "Created directory: $downloadDir" -ForegroundColor Green
} else {
    Write-Host "Using existing directory: $downloadDir" -ForegroundColor Yellow
}

# URLリストを読み込み
$urls = Get-Content $urlsFile | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") }
$totalCount = $urls.Count

Write-Host "Total packages to download: $totalCount" -ForegroundColor Green
Write-Host "Expected packages: ~443 (Basic Next.js + Meal Tracker dependencies)" -ForegroundColor Cyan
Write-Host ""

if ($totalCount -lt 440) {
    Write-Host "Warning: Expected ~443 packages, but found only $totalCount" -ForegroundColor Yellow
    Write-Host "Make sure you've combined both package lists:" -ForegroundColor Yellow
    Write-Host "  1. package-urls.txt (Basic Next.js)" -ForegroundColor White
    Write-Host "  2. meal-tracker-additional-packages.txt (Additional dependencies)" -ForegroundColor White
    Write-Host ""
    $continue = Read-Host "Continue anyway? (y/n)"
    if ($continue -ne "y") {
        exit 0
    }
}

# 統計情報
$downloaded = 0
$skipped = 0
$failed = 0
$startTime = Get-Date

# カテゴリ別カウンター
$categories = @{
    "prisma" = 0
    "zustand" = 0
    "recharts" = 0
    "bcryptjs" = 0
    "next" = 0
    "react" = 0
    "other" = 0
}

# ダウンロード実行
foreach ($i in 0..($urls.Count - 1)) {
    $url = $urls[$i]
    $current = $i + 1
    $fileName = Split-Path $url -Leaf
    $filePath = Join-Path $downloadDir $fileName
    
    # カテゴリ分類
    if ($url -match "prisma") { $categories["prisma"]++ }
    elseif ($url -match "zustand") { $categories["zustand"]++ }
    elseif ($url -match "recharts|d3-") { $categories["recharts"]++ }
    elseif ($url -match "bcrypt") { $categories["bcryptjs"]++ }
    elseif ($url -match "next|@next") { $categories["next"]++ }
    elseif ($url -match "react") { $categories["react"]++ }
    else { $categories["other"]++ }
    
    # プログレスバー
    $percentComplete = [math]::Round(($current / $totalCount) * 100, 1)
    Write-Progress -Activity "Downloading NPM Packages" `
                   -Status "$current of $totalCount - $fileName" `
                   -PercentComplete $percentComplete
    
    # 既にダウンロード済みの場合はスキップ
    if (Test-Path $filePath) {
        $skipped++
        Write-Host "[$current/$totalCount] SKIP: $fileName (already exists)" -ForegroundColor Yellow
        continue
    }
    
    # ダウンロード実行
    try {
        Invoke-WebRequest -Uri $url -OutFile $filePath -ErrorAction Stop -TimeoutSec 30
        $downloaded++
        $fileSize = [math]::Round((Get-Item $filePath).Length / 1MB, 2)
        Write-Host "[$current/$totalCount] OK: $fileName ($fileSize MB)" -ForegroundColor Green
    }
    catch {
        $failed++
        Write-Host "[$current/$totalCount] FAIL: $fileName" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor DarkRed
        
        # 失敗したURLをログに記録
        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $url | $($_.Exception.Message)"
        Add-Content -Path "failed-downloads.log" -Value $logEntry
    }
    
    # レート制限対策（npmレジストリへの負荷軽減）
    Start-Sleep -Milliseconds 100
}

Write-Progress -Activity "Downloading NPM Packages" -Completed

# 完了メッセージ
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Download Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Statistics:" -ForegroundColor White
Write-Host "  Total packages:     $totalCount" -ForegroundColor White
Write-Host "  Downloaded:         $downloaded" -ForegroundColor Green
Write-Host "  Skipped (existing): $skipped" -ForegroundColor Yellow
Write-Host "  Failed:             $failed" -ForegroundColor Red
Write-Host "  Duration:           $($duration.ToString('mm\:ss'))" -ForegroundColor White
Write-Host ""

Write-Host "Package Categories:" -ForegroundColor White
Write-Host "  Prisma:             $($categories['prisma'])" -ForegroundColor Cyan
Write-Host "  Zustand:            $($categories['zustand'])" -ForegroundColor Cyan
Write-Host "  Recharts/D3:        $($categories['recharts'])" -ForegroundColor Cyan
Write-Host "  bcryptjs:           $($categories['bcryptjs'])" -ForegroundColor Cyan
Write-Host "  Next.js:            $($categories['next'])" -ForegroundColor Cyan
Write-Host "  React:              $($categories['react'])" -ForegroundColor Cyan
Write-Host "  Other:              $($categories['other'])" -ForegroundColor Cyan
Write-Host ""

# ファイルサイズの計算
if (Test-Path $downloadDir) {
    $totalSize = (Get-ChildItem -Path $downloadDir -File | Measure-Object -Property Length -Sum).Sum
    $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
    Write-Host "Total download size: $totalSizeMB MB" -ForegroundColor Cyan
}

Write-Host "Files saved to: $downloadDir" -ForegroundColor Cyan

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "Warning: Some downloads failed. Check 'failed-downloads.log' for details." -ForegroundColor Yellow
    Write-Host "You can re-run this script to retry failed downloads." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Copy these files to your offline environment:" -ForegroundColor White
Write-Host "     - $downloadDir folder (all .tgz files)" -ForegroundColor Gray
Write-Host "     - package.json" -ForegroundColor Gray
Write-Host "     - package-lock.json" -ForegroundColor Gray
Write-Host "     - install-offline.ps1" -ForegroundColor Gray
Write-Host "     - All source code files" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. In offline environment:" -ForegroundColor White
Write-Host "     - Run: powershell -ExecutionPolicy Bypass -File install-offline.ps1" -ForegroundColor Gray
Write-Host "     - Setup PostgreSQL database" -ForegroundColor Gray
Write-Host "     - Run: npx prisma migrate dev --name init" -ForegroundColor Gray
Write-Host "     - Run: npm run dev" -ForegroundColor Gray
Write-Host ""

# 重要な依存関係の確認
Write-Host "Verifying critical dependencies:" -ForegroundColor Yellow
$criticalPackages = @(
    "prisma",
    "@prisma/client",
    "zustand",
    "recharts",
    "bcryptjs",
    "next",
    "react",
    "react-dom"
)

$allPresent = $true
foreach ($pkg in $criticalPackages) {
    $found = $urls | Where-Object { $_ -match $pkg }
    if ($found) {
        Write-Host "  ✓ $pkg" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $pkg (MISSING!)" -ForegroundColor Red
        $allPresent = $false
    }
}

if (-not $allPresent) {
    Write-Host ""
    Write-Host "WARNING: Some critical packages are missing!" -ForegroundColor Red
    Write-Host "Please check your meal-tracker-all-packages.txt file." -ForegroundColor Yellow
}

Write-Host ""
