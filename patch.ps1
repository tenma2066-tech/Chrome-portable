# PowerShell version of patch.py
# Encoding: UTF-8 with BOM (Manual)
# Note: This script performs binary patching on chrome.dll

$ErrorActionPreference = 'Stop'

function Kill-ChromeProcesses {
    $msg = "[*] 競合回避のため、既存の Chrome プロセスを終了します..."
    Write-Host $msg -ForegroundColor Cyan
    try {
        Get-Process -Name chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    } catch { }
}

function Main {
    Write-Host "=========================================="
    Write-Host "   Chrome Portable Patcher (PowerShell)   "
    Write-Host "=========================================="
    Write-Host "[STATUS] 開始しています..." -ForegroundColor Yellow

    try {
        Kill-ChromeProcesses

        $baseDir = $PSScriptRoot
        $searchPattern = Join-Path $baseDir "App\Chrome-bin\*\chrome.dll"
        Write-Host "[*] 検索対象: $searchPattern"
        
        $dllPaths = Get-Item $searchPattern -ErrorAction SilentlyContinue

        if (-not $dllPaths) {
            Write-Host "[ERROR] chrome.dll が見つかりませんでした。" -ForegroundColor Red
            Write-Host "  -> スクリプトの配置場所を確認してください。"
            return
        }

        $targets = @(
            @{ Old = "SOFTWARE\Policies\Google\Chrome"; New = "SOFTWARE\Policies\Xoogle\Xhrome" },
            @{ Old = "SOFTWARE\Policies\Google\Update"; New = "SOFTWARE\Policies\Xoogle\Uxdate" }
        )

        foreach ($dll in $dllPaths) {
            Write-Host ("`n[*] 処理中: " + $dll.FullName) -ForegroundColor Cyan
            
            Write-Host "  [*] データを読み込んでいます (大容量のため時間がかかる場合があります)..."
            $fileBytes = [System.IO.File]::ReadAllBytes($dll.FullName)
            $isModified = $false

            foreach ($t in $targets) {
                $oldBytes = [System.Text.Encoding]::Unicode.GetBytes($t.Old)
                $newBytes = [System.Text.Encoding]::Unicode.GetBytes($t.New)

                $foundIndices = @()
                $startIdx = 0
                while ($true) {
                    $idx = [System.Array]::IndexOf($fileBytes, $oldBytes[0], $startIdx)
                    if ($idx -eq -1 -or $idx -gt ($fileBytes.Length - $oldBytes.Length)) { break }
                    
                    $match = $true
                    for ($j = 1; $j -lt $oldBytes.Length; $j++) {
                        if ($fileBytes[$idx + $j] -ne $oldBytes[$j]) {
                            $match = $false
                            break
                        }
                    }
                    
                    if ($match) {
                        $foundIndices += $idx
                        $startIdx = $idx + $oldBytes.Length
                    } else {
                        $startIdx = $idx + 1
                    }
                    if ($startIdx -ge $fileBytes.Length) { break }
                }

                if ($foundIndices.Count -gt 0) {
                    Write-Host ("  [+] '" + $t.Old + "' を " + $foundIndices.Count + " 箇所発見。") -ForegroundColor Green
                    foreach ($idx in $foundIndices) {
                        for ($j = 0; $j -lt $newBytes.Length; $j++) {
                            $fileBytes[$idx + $j] = $newBytes[$j]
                        }
                    }
                    $isModified = $true
                } else {
                    $matchNew = $false
                    $idx = [System.Array]::IndexOf($fileBytes, $newBytes[0], 0)
                    while ($idx -ne -1 -and $idx -le ($fileBytes.Length - $newBytes.Length)) {
                        $match = $true
                        for ($j = 1; $j -lt $newBytes.Length; $j++) {
                            if ($fileBytes[$idx + $j] -ne $newBytes[$j]) { $match = $false; break }
                        }
                        if ($match) { $matchNew = $true; break }
                        $idx = [System.Array]::IndexOf($fileBytes, $newBytes[0], $idx + 1)
                    }

                    if ($matchNew) {
                        Write-Host ("  [i] 既に '" + $t.New + "' へ置換済みです。") -ForegroundColor Gray
                    } else {
                        Write-Host ("  [-] '" + $t.Old + "' は見つかりませんでした。") -ForegroundColor Yellow
                    }
                }
            }

            if ($isModified) {
                Write-Host "  [*] ファイルへ書き戻しています..."
                [System.IO.File]::WriteAllBytes($dll.FullName, $fileBytes)
                Write-Host "  [+] パッチ適用に成功しました。" -ForegroundColor Green
            } else {
                Write-Host "  [i] 変更の必要はありません。"
            }
        }

        Write-Host "`n[+] すべての処理を完了しました。" -ForegroundColor Green

        $launcher = Join-Path $baseDir "GoogleChromePortable.exe"
        if (Test-Path $launcher) {
            Write-Host ("[*] 起動します: " + $launcher)
            Start-Process -FilePath $launcher -WorkingDirectory $baseDir
        } else {
            Write-Warning "GoogleChromePortable.exe が見つからないため、自動起動をスキップします。"
        }

    } catch {
        Write-Host "`n[FATAL ERROR] 重大なエラーが発生しました:" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
}

Main
Write-Host ("`n" + "-" * 40)
Read-Host "Enter キーを押すと終了します"
