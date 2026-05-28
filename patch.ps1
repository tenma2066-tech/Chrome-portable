# PowerShell version of patch.py
# 文字コード: UTF-8 (BOMなし)

$ErrorActionPreference = 'Stop'

function Kill-ChromeProcesses {
    Write-Host "[*] 競合回避のため、既存の Chrome プロセスを終了します..." -ForegroundColor Cyan
    try {
        taskkill /F /IM chrome.exe /T 2>$null
    } catch {
        # Ignore errors if no processes found
    }
}

function Main {
    try {
        Kill-ChromeProcesses

        $baseDir = $PSScriptRoot
        $searchPattern = Join-Path $baseDir "App\Chrome-bin\*\chrome.dll"
        $dllPaths = Get-Item $searchPattern -ErrorAction SilentlyContinue

        if (-not $dllPaths) {
            Write-Host "[ERROR] chrome.dll が見つかりません。" -ForegroundColor Red
            Write-Host "探索パス: $searchPattern"
            return
        }

        # 置換対象 (UTF-16LE バイト列として置換)
        $targets = @(
            @{ Old = "SOFTWARE\Policies\Google\Chrome"; New = "SOFTWARE\Policies\Xoogle\Xhrome" },
            @{ Old = "SOFTWARE\Policies\Google\Update"; New = "SOFTWARE\Policies\Xoogle\Uxdate" }
        )

        foreach ($dll in $dllPaths) {
            Write-Host ("`n[*] ターゲット: " + $dll.FullName) -ForegroundColor Cyan
            
            $fileBytes = [System.IO.File]::ReadAllBytes($dll.FullName)
            $isModified = $false

            foreach ($t in $targets) {
                $oldBytes = [System.Text.Encoding]::Unicode.GetBytes($t.Old)
                $newBytes = [System.Text.Encoding]::Unicode.GetBytes($t.New)

                # バイト列置換 (簡易的な実装)
                # PowerShellでの大規模バイナリ置換は MemoryStream 等が効率的だが、
                # 汎用性を考慮しバイトマッチングを行う
                
                $foundIndices = @()
                for ($i = 0; $i -le ($fileBytes.Length - $oldBytes.Length); $i++) {
                    $match = $true
                    for ($j = 0; $j -lt $oldBytes.Length; $j++) {
                        if ($fileBytes[$i + $j] -ne $oldBytes[$j]) {
                            $match = $false
                            break
                        }
                    }
                    if ($match) {
                        $foundIndices += $i
                        $i += $oldBytes.Length - 1
                    }
                }

                if ($foundIndices.Count -gt 0) {
                    Write-Host ("  [+] '" + $t.Old + "' を " + $foundIndices.Count + " 箇所発見。置換します。") -ForegroundColor Green
                    foreach ($idx in $foundIndices) {
                        for ($j = 0; $j -lt $newBytes.Length; $j++) {
                            $fileBytes[$idx + $j] = $newBytes[$j]
                        }
                    }
                    $isModified = $true
                } else {
                    # 既に置換済みかチェック
                    $matchNew = $false
                    for ($i = 0; $i -le ($fileBytes.Length - $newBytes.Length); $i++) {
                        $match = $true
                        for ($j = 0; $j -lt $newBytes.Length; $j++) {
                            if ($fileBytes[$i + $j] -ne $newBytes[$j]) {
                                $match = $false
                                break
                            }
                        }
                        if ($match) { $matchNew = $true; break }
                    }

                    if ($matchNew) {
                        Write-Host ("  [i] 既に '" + $t.New + "' へ適用済みです。") -ForegroundColor Gray
                    } else {
                        Write-Host ("  [-] '" + $t.Old + "' が見つかりません。") -ForegroundColor Yellow
                    }
                }
            }

            if ($isModified) {
                Write-Host "  [*] 変更を保存中..."
                [System.IO.File]::WriteAllBytes($dll.FullName, $fileBytes)
                Write-Host "  [+] パッチ適用完了。" -ForegroundColor Green
            } else {
                Write-Host "  [i] 変更の必要はありません。"
            }
        }

        Write-Host "`n[+] すべての処理が完了しました。" -ForegroundColor Green

        # 起動
        $launcherCandidates = @(
            (Join-Path $baseDir "GoogleChromePortable.exe"),
            (Join-Path $baseDir "App\Chrome-bin\chrome.exe")
        )

        foreach ($launcher in $launcherCandidates) {
            if (Test-Path $launcher) {
                Write-Host ("[*] 起動します: " + $launcher)
                Start-Process -FilePath $launcher -WorkingDirectory $baseDir
                return
            }
        }
        Write-Warning "起動可能な実行ファイルが見つかりません。"

    } catch {
        Write-Host "`n[FATAL ERROR] 処理中にエラーが発生しました:" -ForegroundColor Red
        $_.Exception | Out-String | Write-Host
    }
}

Main
Write-Host ("`n" + "-" * 40)
Read-Host "Enter キーを押して終了してください"
