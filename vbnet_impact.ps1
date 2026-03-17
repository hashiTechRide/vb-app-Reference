#Requires -Version 7.0
<#
.SYNOPSIS
    VB.NET 2008 CE 影響範囲解析スクリプト（モード横断追跡）
.DESCRIPTION
    スパゲッティコードにおいて、変更対象のオブジェクトが
    他のモード(機能)でも参照されているかを網羅的に一覧化する。
    文字列リテラルによる分岐制御("入庫検品"等)も追跡対象。
    出力: OpenXML Excel (.xlsx)  依存: なし (PowerShell 7.x 標準のみ)
.PARAMETER Path
    プロジェクトフォルダパス
.PARAMETER Target
    追跡対象（変数名/メソッド名/コントロール名/文字列）。カンマ区切りで複数可。
    省略時はファイル全体スキャンモード（全オブジェクト自動検出）
.PARAMETER OutFile
    出力Excelパス（省略時は自動命名）
.PARAMETER ModeVar
    モード分岐に使われている変数名（既定: 自動検出）
    例: -ModeVar "g_FuncMode","g_Mode","strKinou"
.EXAMPLE
    # 対象指定モード: 特定の変数/メソッド/文字列の影響を調査
    .\vbnet_impact.ps1 -Path "C:\Projects\App" -Target "g_FuncMode","btnConfirm","入庫検品"
    # ファイル全体スキャンモード: 全オブジェクトを自動検出して影響一覧
    .\vbnet_impact.ps1 -Path "C:\Projects\App"
    # モード変数を明示指定
    .\vbnet_impact.ps1 -Path "C:\Projects\App" -Target "CheckZaiko" -ModeVar "g_FuncMode"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$Path,
    [string[]]$Target,
    [string]$OutFile,
    [string[]]$ModeVar
)
$ErrorActionPreference = 'Stop'

# ============================================================
# ファイル読み込み
# ============================================================
function Read-VBFile([string]$fp) {
    foreach ($e in @('utf-8','shift_jis','Default')) {
        try { return [IO.File]::ReadAllLines($fp,[Text.Encoding]::GetEncoding($e)) } catch { continue }
    }
    try { return [IO.File]::ReadAllLines($fp) } catch { return @() }
}

# ============================================================
# 解析エンジン
# ============================================================
function Invoke-ImpactAnalysis {
    param([string]$ProjectPath, [string[]]$Targets, [string[]]$ModeVars)

    $allFiles = @(Get-ChildItem -Path $ProjectPath -Filter '*.vb' -Recurse -File |
        Where-Object { $_.Name -notlike '*.Designer.vb' } | Sort-Object FullName)

    Write-Host "  対象ファイル: $($allFiles.Count)" -ForegroundColor Gray

    # ---- 全ファイル読み込み & 行データ構築 ----
    $fileData = [ordered]@{}  # filename -> @{ Path; Lines; Code[] }
    foreach ($f in $allFiles) {
        $lines = Read-VBFile $f.FullName
        $codeLines = @()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $raw = $lines[$i]
            $code = ($raw -replace "'.*$", '').Trim()
            $codeLines += @{ Raw = $raw; Code = $code; Num = $i + 1 }
        }
        $fileData[$f.Name] = @{ Path = $f.FullName; Lines = $lines; CodeLines = $codeLines }
    }

    # ---- モード変数の自動検出 ----
    if (-not $ModeVars -or $ModeVars.Count -eq 0) {
        Write-Host '  モード変数を自動検出中...' -ForegroundColor Gray
        $modeVarCandidates = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        # Public/Friend変数で、Select Case や 複数のIf分岐で参照されているものを検出
        $reGV = [regex]::new('^\s*(Public|Friend)\s+(?:Shared\s+)?(?:Dim\s+|Const\s+)?(\w+)\s+As\s+','IgnoreCase')
        $gvNames = [System.Collections.Generic.List[string]]::new()
        foreach ($fd in $fileData.Values) {
            foreach ($cl in $fd.CodeLines) {
                $mg = $reGV.Match($cl.Code)
                if ($mg.Success) { $gvNames.Add($mg.Groups[2].Value) }
            }
        }
        # Select Case で参照されている変数 = モード変数の可能性大
        $reSelect = [regex]::new('^\s*Select\s+Case\s+(\w+)', 'IgnoreCase')
        foreach ($fd in $fileData.Values) {
            foreach ($cl in $fd.CodeLines) {
                $ms = $reSelect.Match($cl.Code)
                if ($ms.Success) {
                    $vn = $ms.Groups[1].Value
                    if ($gvNames -contains $vn) { [void]$modeVarCandidates.Add($vn) }
                }
            }
        }
        # If で3回以上比較されているグローバル変数もモード変数候補
        foreach ($vn in $gvNames) {
            $ifCount = 0
            foreach ($fd in $fileData.Values) {
                foreach ($cl in $fd.CodeLines) {
                    if ($cl.Code -match "If\s+.*\b$([regex]::Escape($vn))\b") { $ifCount++ }
                }
            }
            if ($ifCount -ge 3) { [void]$modeVarCandidates.Add($vn) }
        }
        $ModeVars = @($modeVarCandidates)
        if ($ModeVars.Count -gt 0) {
            Write-Host "  検出モード変数: $($ModeVars -join ', ')" -ForegroundColor Cyan
        } else {
            Write-Host '  モード変数は自動検出されませんでした' -ForegroundColor Yellow
        }
    }

    # ---- 文字列リテラル（分岐キー）の自動検出 ----
    Write-Host '  文字列リテラル(分岐キー)を検出中...' -ForegroundColor Gray
    $stringLiterals = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]]::new()
    $reStr = [regex]::new('"([^"]+)"')
    foreach ($fn in $fileData.Keys) {
        $fd = $fileData[$fn]
        foreach ($cl in $fd.CodeLines) {
            foreach ($m in $reStr.Matches($cl.Code)) {
                $sv = $m.Groups[1].Value
                # Case文/If文内の文字列 or モード変数への代入内の文字列を分岐キーとみなす
                $isBranchKey = ($cl.Code -match '^\s*Case\s+' -or $cl.Code -match '^\s*(?:Else)?If\s+')
                $isModeAssign = $false
                foreach ($mv in $ModeVars) {
                    if ($cl.Code -match "\b$([regex]::Escape($mv))\s*=") { $isModeAssign = $true; break }
                }
                if ($isBranchKey -or $isModeAssign) {
                    if (-not $stringLiterals.ContainsKey($sv)) {
                        $stringLiterals[$sv] = [System.Collections.Generic.List[string]]::new()
                    }
                    if (-not $stringLiterals[$sv].Contains($fn)) { $stringLiterals[$sv].Add($fn) }
                }
            }
        }
    }
    $detectedKeys = @($stringLiterals.Keys | Where-Object { $stringLiterals[$_].Count -ge 1 })
    if ($detectedKeys.Count -gt 0) {
        Write-Host "  検出分岐キー文字列: $($detectedKeys.Count) 件 ($($detectedKeys | Select-Object -First 5 | ForEach-Object {'"' + $_ + '"'} | Join-String -Separator ', ')...)" -ForegroundColor Cyan
    }

    # ---- ターゲット自動検出 (全体スキャンモード) ----
    $isFullScan = (-not $Targets -or $Targets.Count -eq 0)
    if ($isFullScan) {
        Write-Host '  全体スキャンモード: オブジェクト自動検出中...' -ForegroundColor Cyan
        $autoTargets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

        # グローバル/Friend変数
        $reGV2 = [regex]::new('^\s*(Public|Friend)\s+(?:Shared\s+)?(?:Dim\s+|Const\s+)?(\w+)\s+As\s+','IgnoreCase')
        foreach ($fd in $fileData.Values) {
            foreach ($cl in $fd.CodeLines) {
                $mg = $reGV2.Match($cl.Code); if ($mg.Success) { [void]$autoTargets.Add($mg.Groups[2].Value) }
            }
        }
        # Public メソッド
        $rePM = [regex]::new('^\s*Public\s+(?:Shared\s+)?(?:Overrides\s+)?(?:Sub|Function)\s+(\w+)', 'IgnoreCase')
        foreach ($fd in $fileData.Values) {
            foreach ($cl in $fd.CodeLines) {
                $mm = $rePM.Match($cl.Code); if ($mm.Success) { [void]$autoTargets.Add($mm.Groups[1].Value) }
            }
        }
        # WithEvents コントロール
        $reCtrl = [regex]::new('Friend\s+WithEvents\s+(\w+)\s+As\s+', 'IgnoreCase')
        # Designer ファイルも読む
        $designerFiles = @(Get-ChildItem -Path $ProjectPath -Filter '*.Designer.vb' -Recurse -File)
        foreach ($df in $designerFiles) {
            $dlines = Read-VBFile $df.FullName
            foreach ($dl in $dlines) {
                $mc = $reCtrl.Match($dl); if ($mc.Success) { [void]$autoTargets.Add($mc.Groups[1].Value) }
            }
        }
        # 分岐キー文字列
        foreach ($sk in $detectedKeys) { [void]$autoTargets.Add($sk) }
        # モード変数
        foreach ($mv in $ModeVars) { [void]$autoTargets.Add($mv) }

        $Targets = @($autoTargets | Sort-Object)
        Write-Host "  自動検出ターゲット: $($Targets.Count) 件" -ForegroundColor Cyan
    }

    # ---- 各ターゲットの影響範囲解析 ----
    Write-Host "  影響範囲解析中... ($($Targets.Count) 件)" -ForegroundColor Gray

    $results = [System.Collections.Generic.List[hashtable]]::new()

    # メソッド境界マップ構築: filename -> @( @{Class;Method;Start;End} )
    $methodMap = [ordered]@{}
    $reMethod = [regex]::new('^\s*(Public|Private|Protected|Friend)?\s*(?:Shared\s+)?(?:Overrides\s+)?(?:Sub|Function)\s+(\w+)', 'IgnoreCase')
    $reEndMethod = [regex]::new('^\s*End\s+(Sub|Function)', 'IgnoreCase')
    $reClass = [regex]::new('^\s*(?:Public|Private|Friend|Protected)?\s*(?:Partial\s+)?(?:Class|Module|Structure)\s+(\w+)', 'IgnoreCase')
    foreach ($fn in $fileData.Keys) {
        $fd = $fileData[$fn]; $methods = [System.Collections.Generic.List[hashtable]]::new()
        $curClass = ''; $curMethod = $null
        foreach ($cl in $fd.CodeLines) {
            $mc = $reClass.Match($cl.Code); if ($mc.Success) { $curClass = $mc.Groups[1].Value }
            $mm = $reMethod.Match($cl.Code)
            if ($mm.Success) { $curMethod = @{ Class = $curClass; Method = $mm.Groups[2].Value; Start = $cl.Num; End = $cl.Num } }
            $me = $reEndMethod.Match($cl.Code)
            if ($me.Success -and $curMethod) { $curMethod.End = $cl.Num; $methods.Add($curMethod); $curMethod = $null }
        }
        $methodMap[$fn] = $methods
    }

    # メソッド名を行番号から逆引き
    function Get-MethodAt([string]$fileName, [int]$lineNum) {
        $methods = $methodMap[$fileName]
        if (-not $methods) { return '[トップレベル]' }
        foreach ($m in $methods) {
            if ($lineNum -ge $m.Start -and $lineNum -le $m.End) { return "$($m.Class).$($m.Method)" }
        }
        return '[トップレベル]'
    }

    # モード分岐コンテキスト判定: 行がどのモード(分岐キー)の中にあるか
    function Get-ModeContext([string]$fileName, [int]$lineNum) {
        $fd = $fileData[$fileName]
        if (-not $fd) { return '不明' }
        # 直近のSelect Case/If文を遡って、どのCase/条件下かを判定
        $contexts = [System.Collections.Generic.List[string]]::new()
        $inSelect = $false; $selectVar = ''; $lastCase = ''
        for ($i = 0; $i -lt $fd.CodeLines.Count; $i++) {
            $cl = $fd.CodeLines[$i]
            if ($cl.Num -gt $lineNum) { break }

            # Select Case 開始
            $ms = [regex]::Match($cl.Code, '^\s*Select\s+Case\s+(.+)', 'IgnoreCase')
            if ($ms.Success) {
                $sv = $ms.Groups[1].Value.Trim()
                $isModeSelect = $false
                foreach ($mv in $ModeVars) { if ($sv -match "\b$([regex]::Escape($mv))\b") { $isModeSelect = $true; break } }
                if ($isModeSelect) { $inSelect = $true; $selectVar = $sv; $lastCase = '' }
            }
            if ($inSelect) {
                $mc = [regex]::Match($cl.Code, '^\s*Case\s+(.+)', 'IgnoreCase')
                if ($mc.Success -and -not $cl.Code.Trim().ToLower().StartsWith('select')) {
                    $lastCase = $mc.Groups[1].Value.Trim()
                }
            }
            $me = [regex]::Match($cl.Code, '^\s*End\s+Select', 'IgnoreCase')
            if ($me.Success) { $inSelect = $false }

            # If文でモード変数を比較
            $mIf = [regex]::Match($cl.Code, '^\s*(?:Else)?If\s+(.+?)\s+Then', 'IgnoreCase')
            if ($mIf.Success) {
                $cond = $mIf.Groups[1].Value
                foreach ($mv in $ModeVars) {
                    if ($cond -match "\b$([regex]::Escape($mv))\b") {
                        $lastCase = $cond.Trim()
                        break
                    }
                }
            }
        }

        if ($lastCase) { return $lastCase }
        if ($inSelect -and $selectVar) { return "Select($selectVar) 内" }
        return '共通(分岐外)'
    }

    # ---- ターゲット別の参照箇所を収集 ----
    foreach ($tgt in $Targets) {
        $isStringLiteral = $detectedKeys -contains $tgt
        $isModeVariable = $ModeVars -contains $tgt

        foreach ($fn in $fileData.Keys) {
            $fd = $fileData[$fn]
            foreach ($cl in $fd.CodeLines) {
                $code = $cl.Code
                if ([string]::IsNullOrEmpty($code)) { continue }

                $found = $false
                $matchType = ''

                if ($isStringLiteral) {
                    # 文字列リテラル: ダブルクォート内で完全一致
                    if ($code -match "`"$([regex]::Escape($tgt))`"") {
                        $found = $true; $matchType = '文字列リテラル'
                    }
                } else {
                    # 変数/メソッド/コントロール: 単語境界マッチ
                    if ($code -match "\b$([regex]::Escape($tgt))\b") {
                        $found = $true
                        # 参照種別を判定
                        if ($code -match "\b$([regex]::Escape($tgt))\s*=(?!=)") { $matchType = '書込(代入)' }
                        elseif ($code -match "\b$([regex]::Escape($tgt))\s*\(") { $matchType = '呼出' }
                        elseif ($code -match "\b$([regex]::Escape($tgt))\.\w+\s*=") { $matchType = 'プロパティ設定' }
                        elseif ($code -match "\b$([regex]::Escape($tgt))\.\w+") { $matchType = 'プロパティ参照' }
                        elseif ($code -match '^\s*(Public|Private|Friend|Protected)?\s*(?:Shared\s+)?(?:Dim\s+|Const\s+)?'+ [regex]::Escape($tgt) + '\s+As\s+') { $matchType = '宣言' }
                        elseif ($code -match '^\s*(?:Public|Private|Protected|Friend)?\s*(?:Sub|Function)\s+' + [regex]::Escape($tgt)) { $matchType = 'メソッド定義' }
                        else { $matchType = '参照(読取)' }
                    }
                }

                if ($found) {
                    $methodName = Get-MethodAt $fn $cl.Num
                    $modeCtx = Get-ModeContext $fn $cl.Num

                    # 分岐種別判定
                    $branchType = '-'
                    if ($code -match '^\s*Select\s+Case') { $branchType = 'Select Case' }
                    elseif ($code -match '^\s*Case\s+') { $branchType = 'Case' }
                    elseif ($code -match '^\s*(?:Else)?If\s+') { $branchType = 'If' }

                    # ターゲット種別
                    $tgtType = if ($isStringLiteral) { '分岐キー文字列' }
                               elseif ($isModeVariable) { 'モード変数' }
                               elseif ($code -match "^\s*(?:Public|Private)\s+(?:Sub|Function)\s+$([regex]::Escape($tgt))") { 'メソッド' }
                               elseif ($code -match "WithEvents\s+$([regex]::Escape($tgt))") { 'コントロール' }
                               else { '変数/その他' }

                    $results.Add(@{
                        Target      = $tgt
                        TargetType  = $tgtType
                        File        = $fn
                        Line        = $cl.Num
                        Method      = $methodName
                        RefType     = $matchType
                        ModeContext = $modeCtx
                        BranchType  = $branchType
                        Code        = $cl.Raw.Trim()
                    })
                }
            }
        }
    }

    Write-Host "  検出参照: $($results.Count) 件" -ForegroundColor Cyan

    return @{
        Results     = $results
        Targets     = $Targets
        ModeVars    = $ModeVars
        StringKeys  = $detectedKeys
        FileData    = $fileData
        MethodMap   = $methodMap
    }
}

# ============================================================
# OpenXML Excel 出力
# ============================================================
function Write-XlsxReport {
    param([hashtable]$Analysis, [string]$OutputPath)

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function Esc([string]$s) {
        if(!$s){return ''}
        # XML 1.0 で許可される文字: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD]
        # それ以外の制御文字を除去
        $cleaned = [Text.StringBuilder]::new($s.Length)
        foreach ($ch in $s.ToCharArray()) {
            $code = [int]$ch
            if ($code -eq 0x9 -or $code -eq 0xA -or $code -eq 0xD -or ($code -ge 0x20 -and $code -le 0xD7FF) -or ($code -ge 0xE000 -and $code -le 0xFFFD)) {
                [void]$cleaned.Append($ch)
            }
        }
        return $cleaned.ToString().Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
    }
    function ColRef([int]$c) { $r='';$c++;while($c -gt 0){$c--;$r=[char](65+($c%26))+$r;$c=[math]::Floor($c/26)};$r }
    function MkRow([object[]]$v,[int]$s) { $cells=[System.Collections.Generic.List[hashtable]]::new(); foreach($val in $v){$cells.Add(@{V=$val;S=$s})}; @{Cells=$cells} }

    function SheetXml([hashtable]$sh) {
        $sb=[Text.StringBuilder]::new()
        [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>')
        for($ri=0;$ri -lt $sh.Rows.Count;$ri++){
            $row=$sh.Rows[$ri];$rn=$ri+1;[void]$sb.Append("<row r=`"$rn`">")
            for($ci=0;$ci -lt $row.Cells.Count;$ci++){
                $cell=$row.Cells[$ci];$ref="$(ColRef $ci)$rn";$si=[int]$cell.S
                $v=if($null -ne $cell.V){"$($cell.V)"}else{''}
                $isNum=$false;$nd=0.0;if($v -match '^\-?[\d]+\.?[\d]*$'){$isNum=[double]::TryParse($v,[ref]$nd)}
                if($isNum){[void]$sb.Append("<c r=`"$ref`" s=`"$si`"><v>$v</v></c>")}
                else{[void]$sb.Append("<c r=`"$ref`" s=`"$si`" t=`"inlineStr`"><is><t>$(Esc $v)</t></is></c>")}
            };[void]$sb.Append('</row>')
        };[void]$sb.Append('</sheetData></worksheet>');$sb.ToString()
    }

    $sheets=[System.Collections.Generic.List[hashtable]]::new()
    $res = $Analysis.Results

    # ================================================================
    # Sheet 1: 影響範囲一覧（メイン）
    # ================================================================
    Write-Host '  Sheet: 影響範囲一覧' -ForegroundColor Gray
    $r1=[System.Collections.Generic.List[hashtable]]::new()
    $r1.Add((MkRow @('影響範囲解析 - 参照箇所一覧') 8))
    $r1.Add((MkRow @("解析: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | モード変数: $($Analysis.ModeVars -join ', ')") 9))
    $r1.Add((MkRow @('') 0))
    $h1 = @('No.','対象','種別','ファイル','行','メソッド','参照種別','モードコンテキスト','分岐種別','該当コード')
    $r1.Add((MkRow $h1 1))
    $sorted = @($res | Sort-Object { $_.Target }, { $_.File }, { $_.Line })
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $r = $sorted[$i]; $alt = if ($i % 2 -eq 1) { 3 } else { 0 }
        $codeSnip = $r.Code; if ($codeSnip.Length -gt 100) { $codeSnip = $codeSnip.Substring(0,100) + '...' }
        $row = MkRow @($i+1, $r.Target, $r.TargetType, $r.File, $r.Line, $r.Method, $r.RefType, $r.ModeContext, $r.BranchType, $codeSnip) $alt
        # 色分け: モード変数=黄, 分岐キー文字列=橙, 書込=赤
        if ($r.TargetType -eq 'モード変数') { $row.Cells[1].S = 4 }
        elseif ($r.TargetType -eq '分岐キー文字列') { $row.Cells[1].S = 7 }
        if ($r.RefType -eq '書込(代入)') { $row.Cells[6].S = 5 }
        elseif ($r.RefType -eq 'プロパティ設定') { $row.Cells[6].S = 7 }
        if ($r.ModeContext -ne '共通(分岐外)' -and $r.ModeContext -ne '不明') { $row.Cells[7].S = 4 }
        $r1.Add($row)
    }
    $sheets.Add(@{Name='①影響範囲一覧';Rows=$r1})

    # ================================================================
    # Sheet 2: 対象別サマリー
    # ================================================================
    Write-Host '  Sheet: 対象別サマリー' -ForegroundColor Gray
    $r2=[System.Collections.Generic.List[hashtable]]::new()
    $r2.Add((MkRow @('対象別 影響サマリー') 8))
    $r2.Add((MkRow @('各オブジェクトの参照ファイル数・モード数を一覧化。影響度が高い順にソート。') 9))
    $r2.Add((MkRow @('') 0))
    $h2 = @('No.','対象','種別','参照総数','参照ファイル数','参照メソッド数','モードコンテキスト種類数','書込箇所数','呼出箇所数','影響度','参照ファイル一覧','モードコンテキスト一覧')
    $r2.Add((MkRow $h2 1))

    $grouped = $res | Group-Object { $_.Target }
    $summaries = @($grouped | ForEach-Object {
        $refs = $_.Group
        $files = @($refs | ForEach-Object { $_.File } | Sort-Object -Unique)
        $methods = @($refs | ForEach-Object { $_.Method } | Sort-Object -Unique)
        $modes = @($refs | ForEach-Object { $_.ModeContext } | Where-Object { $_ -ne '共通(分岐外)' -and $_ -ne '不明' } | Sort-Object -Unique)
        $writes = @($refs | Where-Object { $_.RefType -eq '書込(代入)' }).Count
        $calls = @($refs | Where-Object { $_.RefType -eq '呼出' }).Count
        $impact = $files.Count * 3 + $methods.Count + $modes.Count * 5 + $writes * 2
        $ErrorActionPreference = 'Stop'

# ============================================================
# ファイル読み込み
# ============================================================
function Read-VBFile([string]$fp) {
    foreach ($e in @('utf-8','shift_jis','Default')) {
        try { return [IO.File]::ReadAllLines($fp,[Text.Encoding]::GetEncoding($e)) } catch { continue }
    }
    try { return [IO.File]::ReadAllLines($fp) } catch { return @() }
}

# ============================================================
# 解析エンジン
# ============================================================
function Invoke-ImpactAnalysis {
    param([string]$ProjectPath, [string[]]$Targets, [string[]]$ModeVars)

    $allFiles = @(Get-ChildItem -Path $ProjectPath -Filter '*.vb' -Recurse -File |
        Where-Object { $_.Name -notlike '*.Designer.vb' } | Sort-Object FullName)

    Write-Host "  対象ファイル: $($allFiles.Count)" -ForegroundColor Gray

    # ---- 全ファイル読み込み & 行データ構築 ----
    $fileData = [ordered]@{}  # filename -> @{ Path; Lines; Code[] }
    foreach ($f in $allFiles) {
        $lines = Read-VBFile $f.FullName
        $codeLines = @()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $raw = $lines[$i]
            $code = ($raw -replace "'.*$", '').Trim()
            $codeLines += @{ Raw = $raw; Code = $code; Num = $i + 1 }
        }
        $fileData[$f.Name] = @{ Path = $f.FullName; Lines = $lines; CodeLines = $codeLines }
    }

    # ---- モード変数の自動検出 ----
    if (-not $ModeVars -or $ModeVars.Count -eq 0) {
        Write-Host '  モード変数を自動検出中...' -ForegroundColor Gray
        $modeVarCandidates = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        # Public/Friend変数で、Select Case や 複数のIf分岐で参照されているものを検出
        $reGV = [regex]::new('^\s*(Public|Friend)\s+(?:Shared\s+)?(?:Dim\s+|Const\s+)?(\w+)\s+As\s+','IgnoreCase')
        $gvNames = [System.Collections.Generic.List[string]]::new()
        foreach ($fd in $fileData.Values) {
            foreach ($cl in $fd.CodeLines) {
                $mg = $reGV.Match($cl.Code)
                if ($mg.Success) { $gvNames.Add($mg.Groups[2].Value) }
            }
        }
        # Select Case で参照されている変数 = モード変数の可能性大
        $reSelect = [regex]::new('^\s*Select\s+Case\s+(\w+)', 'IgnoreCase')
        foreach ($fd in $fileData.Values) {
            foreach ($cl in $fd.CodeLines) {
                $ms = $reSelect.Match($cl.Code)
                if ($ms.Success) {
                    $vn = $ms.Groups[1].Value
                    if ($gvNames -contains $vn) { [void]$modeVarCandidates.Add($vn) }
                }
            }
        }
        # If で3回以上比較されているグローバル変数もモード変数候補
        foreach ($vn in $gvNames) {
            $ifCount = 0
            foreach ($fd in $fileData.Values) {
                foreach ($cl in $fd.CodeLines) {
                    if ($cl.Code -match "If\s+.*\b$([regex]::Escape($vn))\b") { $ifCount++ }
                }
            }
            if ($ifCount -ge 3) { [void]$modeVarCandidates.Add($vn) }
        }
        $ModeVars = @($modeVarCandidates)
        if ($ModeVars.Count -gt 0) {
            Write-Host "  検出モード変数: $($ModeVars -join ', ')" -ForegroundColor Cyan
        } else {
            Write-Host '  モード変数は自動検出されませんでした' -ForegroundColor Yellow
        }
    }

    # ---- 文字列リテラル（分岐キー）の自動検出 ----
    Write-Host '  文字列リテラル(分岐キー)を検出中...' -ForegroundColor Gray
    $stringLiterals = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]]::new()
    $reStr = [regex]::new('"([^"]+)"')
    foreach ($fn in $fileData.Keys) {
        $fd = $fileData[$fn]
        foreach ($cl in $fd.CodeLines) {
            foreach ($m in $reStr.Matches($cl.Code)) {
                $sv = $m.Groups[1].Value
                # Case文/If文内の文字列 or モード変数への代入内の文字列を分岐キーとみなす
                $isBranchKey = ($cl.Code -match '^\s*Case\s+' -or $cl.Code -match '^\s*(?:Else)?If\s+')
                $isModeAssign = $false
                foreach ($mv in $ModeVars) {
                    if ($cl.Code -match "\b$([regex]::Escape($mv))\s*=") { $isModeAssign = $true; break }
                }
                if ($isBranchKey -or $isModeAssign) {
                    if (-not $stringLiterals.ContainsKey($sv)) {
                        $stringLiterals[$sv] = [System.Collections.Generic.List[string]]::new()
                    }
                    if (-not $stringLiterals[$sv].Contains($fn)) { $stringLiterals[$sv].Add($fn) }
                }
            }
        }
    }
    $detectedKeys = @($stringLiterals.Keys | Where-Object { $stringLiterals[$_].Count -ge 1 })
    if ($detectedKeys.Count -gt 0) {
        Write-Host "  検出分岐キー文字列: $($detectedKeys.Count) 件 ($($detectedKeys | Select-Object -First 5 | ForEach-Object {'"' + $_ + '"'} | Join-String -Separator ', ')...)" -ForegroundColor Cyan
    }

    # ---- ターゲット自動検出 (全体スキャンモード) ----
    $isFullScan = (-not $Targets -or $Targets.Count -eq 0)
    if ($isFullScan) {
        Write-Host '  全体スキャンモード: オブジェクト自動検出中...' -ForegroundColor Cyan
        $autoTargets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

        # グローバル/Friend変数
        $reGV2 = [regex]::new('^\s*(Public|Friend)\s+(?:Shared\s+)?(?:Dim\s+|Const\s+)?(\w+)\s+As\s+','IgnoreCase')
        foreach ($fd in $fileData.Values) {
            foreach ($cl in $fd.CodeLines) {
                $mg = $reGV2.Match($cl.Code); if ($mg.Success) { [void]$autoTargets.Add($mg.Groups[2].Value) }
            }
        }
        # Public メソッド
        $rePM = [regex]::new('^\s*Public\s+(?:Shared\s+)?(?:Overrides\s+)?(?:Sub|Function)\s+(\w+)', 'IgnoreCase')
        foreach ($fd in $fileData.Values) {
            foreach ($cl in $fd.CodeLines) {
                $mm = $rePM.Match($cl.Code); if ($mm.Success) { [void]$autoTargets.Add($mm.Groups[1].Value) }
            }
        }
        # WithEvents コントロール
        $reCtrl = [regex]::new('Friend\s+WithEvents\s+(\w+)\s+As\s+', 'IgnoreCase')
        # Designer ファイルも読む
        $designerFiles = @(Get-ChildItem -Path $ProjectPath -Filter '*.Designer.vb' -Recurse -File)
        foreach ($df in $designerFiles) {
            $dlines = Read-VBFile $df.FullName
            foreach ($dl in $dlines) {
                $mc = $reCtrl.Match($dl); if ($mc.Success) { [void]$autoTargets.Add($mc.Groups[1].Value) }
            }
        }
        # 分岐キー文字列
        foreach ($sk in $detectedKeys) { [void]$autoTargets.Add($sk) }
        # モード変数
        foreach ($mv in $ModeVars) { [void]$autoTargets.Add($mv) }

        $Targets = @($autoTargets | Sort-Object)
        Write-Host "  自動検出ターゲット: $($Targets.Count) 件" -ForegroundColor Cyan
    }

    # ---- 各ターゲットの影響範囲解析 ----
    Write-Host "  影響範囲解析中... ($($Targets.Count) 件)" -ForegroundColor Gray

    $results = [System.Collections.Generic.List[hashtable]]::new()

    # メソッド境界マップ構築: filename -> @( @{Class;Method;Start;End} )
    $methodMap = [ordered]@{}
    $reMethod = [regex]::new('^\s*(Public|Private|Protected|Friend)?\s*(?:Shared\s+)?(?:Overrides\s+)?(?:Sub|Function)\s+(\w+)', 'IgnoreCase')
    $reEndMethod = [regex]::new('^\s*End\s+(Sub|Function)', 'IgnoreCase')
    $reClass = [regex]::new('^\s*(?:Public|Private|Friend|Protected)?\s*(?:Partial\s+)?(?:Class|Module|Structure)\s+(\w+)', 'IgnoreCase')
    foreach ($fn in $fileData.Keys) {
        $fd = $fileData[$fn]; $methods = [System.Collections.Generic.List[hashtable]]::new()
        $curClass = ''; $curMethod = $null
        foreach ($cl in $fd.CodeLines) {
            $mc = $reClass.Match($cl.Code); if ($mc.Success) { $curClass = $mc.Groups[1].Value }
            $mm = $reMethod.Match($cl.Code)
            if ($mm.Success) { $curMethod = @{ Class = $curClass; Method = $mm.Groups[2].Value; Start = $cl.Num; End = $cl.Num } }
            $me = $reEndMethod.Match($cl.Code)
            if ($me.Success -and $curMethod) { $curMethod.End = $cl.Num; $methods.Add($curMethod); $curMethod = $null }
        }
        $methodMap[$fn] = $methods
    }

    # メソッド名を行番号から逆引き
    function Get-MethodAt([string]$fileName, [int]$lineNum) {
        $methods = $methodMap[$fileName]
        if (-not $methods) { return '[トップレベル]' }
        foreach ($m in $methods) {
            if ($lineNum -ge $m.Start -and $lineNum -le $m.End) { return "$($m.Class).$($m.Method)" }
        }
        return '[トップレベル]'
    }

    # モード分岐コンテキスト判定: 行がどのモード(分岐キー)の中にあるか
    function Get-ModeContext([string]$fileName, [int]$lineNum) {
        $fd = $fileData[$fileName]
        if (-not $fd) { return '不明' }
        # 直近のSelect Case/If文を遡って、どのCase/条件下かを判定
        $contexts = [System.Collections.Generic.List[string]]::new()
        $inSelect = $false; $selectVar = ''; $lastCase = ''
        for ($i = 0; $i -lt $fd.CodeLines.Count; $i++) {
            $cl = $fd.CodeLines[$i]
            if ($cl.Num -gt $lineNum) { break }

            # Select Case 開始
            $ms = [regex]::Match($cl.Code, '^\s*Select\s+Case\s+(.+)', 'IgnoreCase')
            if ($ms.Success) {
                $sv = $ms.Groups[1].Value.Trim()
                $isModeSelect = $false
                foreach ($mv in $ModeVars) { if ($sv -match "\b$([regex]::Escape($mv))\b") { $isModeSelect = $true; break } }
                if ($isModeSelect) { $inSelect = $true; $selectVar = $sv; $lastCase = '' }
            }
            if ($inSelect) {
                $mc = [regex]::Match($cl.Code, '^\s*Case\s+(.+)', 'IgnoreCase')
                if ($mc.Success -and -not $cl.Code.Trim().ToLower().StartsWith('select')) {
                    $lastCase = $mc.Groups[1].Value.Trim()
                }
            }
            $me = [regex]::Match($cl.Code, '^\s*End\s+Select', 'IgnoreCase')
            if ($me.Success) { $inSelect = $false }

            # If文でモード変数を比較
            $mIf = [regex]::Match($cl.Code, '^\s*(?:Else)?If\s+(.+?)\s+Then', 'IgnoreCase')
            if ($mIf.Success) {
                $cond = $mIf.Groups[1].Value
                foreach ($mv in $ModeVars) {
                    if ($cond -match "\b$([regex]::Escape($mv))\b") {
                        $lastCase = $cond.Trim()
                        break
                    }
                }
            }
        }

        if ($lastCase) { return $lastCase }
        if ($inSelect -and $selectVar) { return "Select($selectVar) 内" }
        return '共通(分岐外)'
    }

    # ---- ターゲット別の参照箇所を収集 ----
    foreach ($tgt in $Targets) {
        $isStringLiteral = $detectedKeys -contains $tgt
        $isModeVariable = $ModeVars -contains $tgt

        foreach ($fn in $fileData.Keys) {
            $fd = $fileData[$fn]
            foreach ($cl in $fd.CodeLines) {
                $code = $cl.Code
                if ([string]::IsNullOrEmpty($code)) { continue }

                $found = $false
                $matchType = ''

                if ($isStringLiteral) {
                    # 文字列リテラル: ダブルクォート内で完全一致
                    if ($code -match "`"$([regex]::Escape($tgt))`"") {
                        $found = $true; $matchType = '文字列リテラル'
                    }
                } else {
                    # 変数/メソッド/コントロール: 単語境界マッチ
                    if ($code -match "\b$([regex]::Escape($tgt))\b") {
                        $found = $true
                        # 参照種別を判定
                        if ($code -match "\b$([regex]::Escape($tgt))\s*=(?!=)") { $matchType = '書込(代入)' }
                        elseif ($code -match "\b$([regex]::Escape($tgt))\s*\(") { $matchType = '呼出' }
                        elseif ($code -match "\b$([regex]::Escape($tgt))\.\w+\s*=") { $matchType = 'プロパティ設定' }
                        elseif ($code -match "\b$([regex]::Escape($tgt))\.\w+") { $matchType = 'プロパティ参照' }
                        elseif ($code -match '^\s*(Public|Private|Friend|Protected)?\s*(?:Shared\s+)?(?:Dim\s+|Const\s+)?'+ [regex]::Escape($tgt) + '\s+As\s+') { $matchType = '宣言' }
                        elseif ($code -match '^\s*(?:Public|Private|Protected|Friend)?\s*(?:Sub|Function)\s+' + [regex]::Escape($tgt)) { $matchType = 'メソッド定義' }
                        else { $matchType = '参照(読取)' }
                    }
                }

                if ($found) {
                    $methodName = Get-MethodAt $fn $cl.Num
                    $modeCtx = Get-ModeContext $fn $cl.Num

                    # 分岐種別判定
                    $branchType = '-'
                    if ($code -match '^\s*Select\s+Case') { $branchType = 'Select Case' }
                    elseif ($code -match '^\s*Case\s+') { $branchType = 'Case' }
                    elseif ($code -match '^\s*(?:Else)?If\s+') { $branchType = 'If' }

                    # ターゲット種別
                    $tgtType = if ($isStringLiteral) { '分岐キー文字列' }
                               elseif ($isModeVariable) { 'モード変数' }
                               elseif ($code -match "^\s*(?:Public|Private)\s+(?:Sub|Function)\s+$([regex]::Escape($tgt))") { 'メソッド' }
                               elseif ($code -match "WithEvents\s+$([regex]::Escape($tgt))") { 'コントロール' }
                               else { '変数/その他' }

                    $results.Add(@{
                        Target      = $tgt
                        TargetType  = $tgtType
                        File        = $fn
                        Line        = $cl.Num
                        Method      = $methodName
                        RefType     = $matchType
                        ModeContext = $modeCtx
                        BranchType  = $branchType
                        Code        = $cl.Raw.Trim()
                    })
                }
            }
        }
    }

    Write-Host "  検出参照: $($results.Count) 件" -ForegroundColor Cyan

    return @{
        Results     = $results
        Targets     = $Targets
        ModeVars    = $ModeVars
        StringKeys  = $detectedKeys
        FileData    = $fileData
        MethodMap   = $methodMap
    }
}

# ============================================================
# OpenXML Excel 出力
# ============================================================
function Write-XlsxReport {
    param([hashtable]$Analysis, [string]$OutputPath)

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function Esc([string]$s) { if(!$s){return ''}; $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;') }
    function ColRef([int]$c) { $r='';$c++;while($c -gt 0){$c--;$r=[char](65+($c%26))+$r;$c=[math]::Floor($c/26)};$r }
    function MkRow([object[]]$v,[int]$s) { $cells=[System.Collections.Generic.List[hashtable]]::new(); foreach($val in $v){$cells.Add(@{V=$val;S=$s})}; @{Cells=$cells} }

    function SheetXml([hashtable]$sh) {
        $sb=[Text.StringBuilder]::new()
        [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>')
        for($ri=0;$ri -lt $sh.Rows.Count;$ri++){
            $row=$sh.Rows[$ri];$rn=$ri+1;[void]$sb.Append("<row r=`"$rn`">")
            for($ci=0;$ci -lt $row.Cells.Count;$ci++){
                $cell=$row.Cells[$ci];$ref="$(ColRef $ci)$rn";$si=[int]$cell.S
                $v=if($null -ne $cell.V){"$($cell.V)"}else{''}
                $isNum=$false;$nd=0.0;if($v -match '^\-?[\d]+\.?[\d]*$'){$isNum=[double]::TryParse($v,[ref]$nd)}
                if($isNum){[void]$sb.Append("<c r=`"$ref`" s=`"$si`"><v>$v</v></c>")}
                else{[void]$sb.Append("<c r=`"$ref`" s=`"$si`" t=`"inlineStr`"><is><t>$(Esc $v)</t></is></c>")}
            };[void]$sb.Append('</row>')
        };[void]$sb.Append('</sheetData></worksheet>');$sb.ToString()
    }

    $sheets=[System.Collections.Generic.List[hashtable]]::new()
    $res = $Analysis.Results

    # ================================================================
    # Sheet 1: 影響範囲一覧（メイン）
    # ================================================================
    Write-Host '  Sheet: 影響範囲一覧' -ForegroundColor Gray
    $r1=[System.Collections.Generic.List[hashtable]]::new()
    $r1.Add((MkRow @('影響範囲解析 - 参照箇所一覧') 8))
    $r1.Add((MkRow @("解析: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | モード変数: $($Analysis.ModeVars -join ', ')") 9))
    $r1.Add((MkRow @('') 0))
    $h1 = @('No.','対象','種別','ファイル','行','メソッド','参照種別','モードコンテキスト','分岐種別','該当コード')
    $r1.Add((MkRow $h1 1))
    $sorted = @($res | Sort-Object { $_.Target }, { $_.File }, { $_.Line })
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $r = $sorted[$i]; $alt = if ($i % 2 -eq 1) { 3 } else { 0 }
        $codeSnip = $r.Code; if ($codeSnip.Length -gt 100) { $codeSnip = $codeSnip.Substring(0,100) + '...' }
        $row = MkRow @($i+1, $r.Target, $r.TargetType, $r.File, $r.Line, $r.Method, $r.RefType, $r.ModeContext, $r.BranchType, $codeSnip) $alt
        # 色分け: モード変数=黄, 分岐キー文字列=橙, 書込=赤
        if ($r.TargetType -eq 'モード変数') { $row.Cells[1].S = 4 }
        elseif ($r.TargetType -eq '分岐キー文字列') { $row.Cells[1].S = 7 }
        if ($r.RefType -eq '書込(代入)') { $row.Cells[6].S = 5 }
        elseif ($r.RefType -eq 'プロパティ設定') { $row.Cells[6].S = 7 }
        if ($r.ModeContext -ne '共通(分岐外)' -and $r.ModeContext -ne '不明') { $row.Cells[7].S = 4 }
        $r1.Add($row)
    }
    $sheets.Add(@{Name='①影響範囲一覧';Rows=$r1})

    # ================================================================
    # Sheet 2: 対象別サマリー
    # ================================================================
    Write-Host '  Sheet: 対象別サマリー' -ForegroundColor Gray
    $r2=[System.Collections.Generic.List[hashtable]]::new()
    $r2.Add((MkRow @('対象別 影響サマリー') 8))
    $r2.Add((MkRow @('各オブジェクトの参照ファイル数・モード数を一覧化。影響度が高い順にソート。') 9))
    $r2.Add((MkRow @('') 0))
    $h2 = @('No.','対象','種別','参照総数','参照ファイル数','参照メソッド数','モードコンテキスト種類数','書込箇所数','呼出箇所数','影響度','参照ファイル一覧','モードコンテキスト一覧')
    $r2.Add((MkRow $h2 1))

    $grouped = $res | Group-Object { $_.Target }
    $summaries = @($grouped | ForEach-Object {
        $refs = $_.Group
        $files = @($refs | ForEach-Object { $_.File } | Sort-Object -Unique)
        $methods = @($refs | ForEach-Object { $_.Method } | Sort-Object -Unique)
        $modes = @($refs | ForEach-Object { $_.ModeContext } | Where-Object { $_ -ne '共通(分岐外)' -and $_ -ne '不明' } | Sort-Object -Unique)
        $writes = @($refs | Where-Object { $_.RefType -eq '書込(代入)' }).Count
        $calls = @($refs | Where-Object { $_.RefType -eq '呼出' }).Count
        $impact = $files.Count * 3 + $methods.Count + $modes.Count * 5 + $writes * 2
        [PSCustomObject]@{
            Target = $_.Name; Type = $refs[0].TargetType
            RefCount = $refs.Count; FileCount = $files.Count; MethodCount = $methods.Count
            ModeCount = $modes.Count; WriteCount = $writes; CallCount = $calls
            Impact = $impact; Files = $files -join ', '; Modes = $modes -join ', '
        }
    } | Sort-Object Impact -Descending)

    for ($i = 0; $i -lt $summaries.Count; $i++) {
        $s = $summaries[$i]; $alt = if ($i % 2 -eq 1) { 3 } else { 0 }
        $impactLabel = if ($s.Impact -ge 30) { "高($($s.Impact))" } elseif ($s.Impact -ge 15) { "中($($s.Impact))" } else { "低($($s.Impact))" }
        $row = MkRow @($i+1, $s.Target, $s.Type, $s.RefCount, $s.FileCount, $s.MethodCount, $s.ModeCount, $s.WriteCount, $s.CallCount, $impactLabel, $s.Files, $s.Modes) $alt
        if ($s.Impact -ge 30) { $row.Cells[9].S = 5 }
        elseif ($s.Impact -ge 15) { $row.Cells[9].S = 4 }
        else { $row.Cells[9].S = 6 }
        if ($s.ModeCount -ge 2) { $row.Cells[6].S = 5 }
        $r2.Add($row)
    }
    $sheets.Add(@{Name='②対象別サマリー';Rows=$r2})

    # ================================================================
    # Sheet 3: モード横断マトリクス
    # ================================================================
    Write-Host '  Sheet: モード横断マトリクス' -ForegroundColor Gray
    $r3=[System.Collections.Generic.List[hashtable]]::new()
    $r3.Add((MkRow @('モード横断 影響マトリクス') 8))
    $r3.Add((MkRow @('行=対象オブジェクト, 列=モードコンテキスト. ○=参照あり ●=書込あり') 9))
    $r3.Add((MkRow @('') 0))

    # モードコンテキスト一覧
    $allModes = @($res | ForEach-Object { $_.ModeContext } | Sort-Object -Unique)
    $hdr = @('対象','種別') + $allModes + @('共通(分岐外)参照数','モード固有参照数')
    $r3.Add((MkRow $hdr 1))

    $impactTargets = @($summaries | Where-Object { $_.Impact -ge 10 } | Select-Object -First 100)
    for ($i = 0; $i -lt $impactTargets.Count; $i++) {
        $t = $impactTargets[$i]; $alt = if ($i % 2 -eq 1) { 3 } else { 0 }
        $tgtRefs = @($res | Where-Object { $_.Target -eq $t.Target })
        $vals = @($t.Target, $t.Type)
        $commonCount = 0; $modeSpecific = 0
        foreach ($mode in $allModes) {
            $modeRefs = @($tgtRefs | Where-Object { $_.ModeContext -eq $mode })
            if ($mode -eq '共通(分岐外)') {
                $commonCount = $modeRefs.Count
                $vals += if ($modeRefs.Count -gt 0) { "$($modeRefs.Count)" } else { '' }
            } else {
                $hasWrite = @($modeRefs | Where-Object { $_.RefType -eq '書込(代入)' -or $_.RefType -eq 'プロパティ設定' }).Count -gt 0
                if ($modeRefs.Count -gt 0) { $modeSpecific += $modeRefs.Count }
                $vals += if ($hasWrite) { "●$($modeRefs.Count)" } elseif ($modeRefs.Count -gt 0) { "○$($modeRefs.Count)" } else { '' }
            }
        }
        $vals += @($commonCount, $modeSpecific)
        $row = MkRow $vals $alt
        if ($modeSpecific -gt 0 -and $commonCount -gt 0) { $row.Cells[0].S = 4 }  # 共通+モード固有 = 黄色(要注意)
        $r3.Add($row)
    }
    $sheets.Add(@{Name='③モード横断マトリクス';Rows=$r3})

    # ================================================================
    # Sheet 4: 分岐キー文字列マップ
    # ================================================================
    Write-Host '  Sheet: 分岐キー文字列' -ForegroundColor Gray
    $r4=[System.Collections.Generic.List[hashtable]]::new()
    $r4.Add((MkRow @('分岐キー文字列マップ') 8))
    $r4.Add((MkRow @('文字列リテラルによるモード分岐の全箇所。Case文やIf文で使われている文字列を追跡。') 9))
    $r4.Add((MkRow @('') 0))
    $h4 = @('No.','文字列','ファイル','行','メソッド','モードコンテキスト','使用箇所(分岐/代入/その他)','該当コード')
    $r4.Add((MkRow $h4 2))
    $strRefs = @($res | Where-Object { $_.TargetType -eq '分岐キー文字列' } | Sort-Object { $_.Target }, { $_.File }, { $_.Line })
    for ($i = 0; $i -lt $strRefs.Count; $i++) {
        $r = $strRefs[$i]; $alt = if ($i % 2 -eq 1) { 3 } else { 0 }
        $codeSnip = $r.Code; if ($codeSnip.Length -gt 80) { $codeSnip = $codeSnip.Substring(0,80) + '...' }
        $usage = if ($r.BranchType -ne '-') { "分岐($($r.BranchType))" } elseif ($r.RefType -eq '書込(代入)') { '代入' } else { 'その他' }
        $row = MkRow @($i+1, "`"$($r.Target)`"", $r.File, $r.Line, $r.Method, $r.ModeContext, $usage, $codeSnip) $alt
        $r4.Add($row)
    }
    $sheets.Add(@{Name='④分岐キー文字列';Rows=$r4})

    # ================================================================
    # Sheet 5: 変更影響チェックリスト
    # ================================================================
    Write-Host '  Sheet: 変更影響チェックリスト' -ForegroundColor Gray
    $r5=[System.Collections.Generic.List[hashtable]]::new()
    $r5.Add((MkRow @('変更影響チェックリスト') 8))
    $r5.Add((MkRow @('影響度が高い順。変更前に全行を確認すること。チェック欄を活用してください。') 9))
    $r5.Add((MkRow @('') 0))
    $h5 = @('チェック','対象','種別','影響度','参照ファイル数','モード数','変更時の注意点','確認メソッド一覧')
    $r5.Add((MkRow $h5 2))
    for ($i = 0; $i -lt $summaries.Count; $i++) {
        $s = $summaries[$i]; $alt = if ($i % 2 -eq 1) { 3 } else { 0 }
        $impactLabel = if ($s.Impact -ge 30) { '高' } elseif ($s.Impact -ge 15) { '中' } else { '低' }
        # 注意点の自動生成
        $warnings = [System.Collections.Generic.List[string]]::new()
        if ($s.ModeCount -ge 2) { $warnings.Add("$($s.ModeCount) モードで参照。全モードのテストが必要。") }
        if ($s.WriteCount -gt 1) { $warnings.Add("$($s.WriteCount) 箇所で書込。副作用に注意。") }
        if ($s.FileCount -ge 3) { $warnings.Add("$($s.FileCount) ファイルに分散。変更漏れに注意。") }
        if ($s.Type -eq '分岐キー文字列') { $warnings.Add('文字列一致で分岐制御。typoに注意。') }
        if ($s.Type -eq 'モード変数') { $warnings.Add('モード分岐の根幹。全機能に影響。') }
        $warn = if ($warnings.Count -gt 0) { $warnings -join ' / ' } else { '-' }

        $tgtRefs = @($res | Where-Object { $_.Target -eq $s.Target })
        $methodList = ($tgtRefs | ForEach-Object { $_.Method } | Sort-Object -Unique) -join "`n"

        $row = MkRow @('□', $s.Target, $s.Type, $impactLabel, $s.FileCount, $s.ModeCount, $warn, $methodList) $alt
        if ($s.Impact -ge 30) { $row.Cells[3].S = 5 } elseif ($s.Impact -ge 15) { $row.Cells[3].S = 4 } else { $row.Cells[3].S = 6 }
        $r5.Add($row)
    }
    $sheets.Add(@{Name='⑤変更チェックリスト';Rows=$r5})

    # ================================================================
    # xlsx パッケージ構築
    # ================================================================
    Write-Host '  xlsx構築中...' -ForegroundColor Gray
    if(Test-Path $OutputPath){Remove-Item $OutputPath -Force}
    $td=Join-Path ([IO.Path]::GetTempPath()) "xlsx_impact_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $td -Force|Out-Null
    try {
        $ct='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        for($i=0;$i -lt $sheets.Count;$i++){$ct+="<Override PartName=`"/xl/worksheets/sheet$($i+1).xml`" ContentType=`"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml`"/>"}
        $ct+='</Types>'; [IO.File]::WriteAllText("$td/[Content_Types].xml",$ct,[Text.Encoding]::UTF8)

        New-Item "$td/_rels" -ItemType Directory -Force|Out-Null
        [IO.File]::WriteAllText("$td/_rels/.rels",'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',[Text.Encoding]::UTF8)

        New-Item "$td/xl/_rels" -ItemType Directory -Force|Out-Null; New-Item "$td/xl/worksheets" -ItemType Directory -Force|Out-Null
        $wr='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        for($i=0;$i -lt $sheets.Count;$i++){$wr+="<Relationship Id=`"rId$($i+1)`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet`" Target=`"worksheets/sheet$($i+1).xml`"/>"}
        $wr+='</Relationships>'; [IO.File]::WriteAllText("$td/xl/_rels/workbook.xml.rels",$wr,[Text.Encoding]::UTF8)

        $wb='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        for($i=0;$i -lt $sheets.Count;$i++){$wb+="<sheet name=`"$(Esc $sheets[$i].Name)`" sheetId=`"$($i+1)`" r:id=`"rId$($i+1)`"/>"}
        $wb+='</sheets></workbook>'; [IO.File]::WriteAllText("$td/xl/workbook.xml",$wb,[Text.Encoding]::UTF8)

        $sty=@'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="4"><font><sz val="10"/><name val="Arial"/></font><font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font><font><b/><sz val="14"/><color rgb="FF1F3864"/><name val="Arial"/></font><font><i/><sz val="9"/><color rgb="FF666666"/><name val="Arial"/></font></fonts>
<fills count="9"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1F3864"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFC00000"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF2F2F2"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFF2CC"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFCE4EC"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE2EFDA"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFBE5D6"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFB0B0B0"/></left><right style="thin"><color rgb="FFB0B0B0"/></right><top style="thin"><color rgb="FFB0B0B0"/></top><bottom style="thin"><color rgb="FFB0B0B0"/></bottom><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="10">
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment wrapText="1"/></xf>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="5" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="6" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="7" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="8" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment wrapText="1"/></xf>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment wrapText="1"/></xf>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment wrapText="1"/></xf>
</cellXfs></styleSheet>
'@
        [IO.File]::WriteAllText("$td/xl/styles.xml",$sty,[Text.Encoding]::UTF8)

        for($si=0;$si -lt $sheets.Count;$si++){
            [IO.File]::WriteAllText("$td/xl/worksheets/sheet$($si+1).xml",(SheetXml $sheets[$si]),[Text.Encoding]::UTF8)
        }
        [IO.Compression.ZipFile]::CreateFromDirectory($td,$OutputPath,[IO.Compression.CompressionLevel]::Optimal,$false)
        Write-Host "  保存完了: $OutputPath" -ForegroundColor Green
    }
    catch {
        Write-Host '' -ForegroundColor Red
        Write-Host '===== エラー詳細 =====' -ForegroundColor Red
        Write-Host "メッセージ : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "例外型     : $($_.Exception.GetType().FullName)" -ForegroundColor Red
        Write-Host "発生箇所   : $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        Write-Host "該当行     : $($_.InvocationInfo.Line.Trim())" -ForegroundColor Yellow
        Write-Host '--- スタックトレース ---' -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        $inner=$_.Exception.InnerException; while($inner){Write-Host "  内部: $($inner.Message)" -ForegroundColor DarkRed; $inner=$inner.InnerException}
        Write-Host '=====================' -ForegroundColor Red; throw
    }
    finally { if(Test-Path $td){Remove-Item $td -Recurse -Force} }
}

# ============================================================
# メイン
# ============================================================
$resolvedPath=(Resolve-Path $Path).Path
if(-not $OutFile){$OutFile=Join-Path (Get-Location) "vbnet_impact_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"}
$OutFile=[IO.Path]::GetFullPath($OutFile)

Write-Host ('='*60) -ForegroundColor Cyan
Write-Host '  VB.NET 影響範囲解析 (モード横断追跡)' -ForegroundColor Cyan
Write-Host ('='*60) -ForegroundColor Cyan
Write-Host "  対象: $resolvedPath"; Write-Host "  出力: $OutFile"
if ($Target) { Write-Host "  追跡: $($Target -join ', ')" -ForegroundColor Yellow }
else { Write-Host '  モード: 全体スキャン (自動検出)' -ForegroundColor Yellow }
Write-Host ''

try {
    Write-Host '[1/3] 影響範囲解析...' -ForegroundColor Cyan
    $analysis = Invoke-ImpactAnalysis -ProjectPath $resolvedPath -Targets $Target -ModeVars $ModeVar

    Write-Host '[2/3] Excelレポート生成...' -ForegroundColor Cyan
    Write-XlsxReport -Analysis $analysis -OutputPath $OutFile

    Write-Host ''; Write-Host '完了!' -ForegroundColor Green; Write-Host "ファイル: $OutFile" -ForegroundColor Green
}
catch {
    Write-Host '' -ForegroundColor Red
    Write-Host '======================================' -ForegroundColor Red
    Write-Host '  エラーが発生しました' -ForegroundColor Red
    Write-Host '======================================' -ForegroundColor Red
    Write-Host "メッセージ : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "例外型     : $($_.Exception.GetType().FullName)" -ForegroundColor Red
    Write-Host "発生箇所   : $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "該当行     : $($_.InvocationInfo.Line.Trim())" -ForegroundColor Yellow
    Write-Host '--- スタックトレース ---' -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    $inner=$_.Exception.InnerException; while($inner){Write-Host "  内部: $($inner.Message)" -ForegroundColor DarkRed; $inner=$inner.InnerException}
    Write-Host '======================================' -ForegroundColor Red; exit 1
}
