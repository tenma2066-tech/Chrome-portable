$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;

public static class ChromePatchHelper
{
    public static int Count(byte[] data, byte[] pattern)
    {
        if (data == null || pattern == null) return 0;
        if (pattern.Length == 0 || data.Length < pattern.Length) return 0;

        int count = 0;
        int limit = data.Length - pattern.Length;

        for (int i = 0; i <= limit; i++)
        {
            if (data[i] != pattern[0])
            {
                continue;
            }

            bool match = true;
            for (int j = 1; j < pattern.Length; j++)
            {
                if (data[i + j] != pattern[j])
                {
                    match = false;
                    break;
                }
            }

            if (match)
            {
                count++;
                i += pattern.Length - 1;
            }
        }

        return count;
    }

    public static int Replace(byte[] data, byte[] oldBytes, byte[] newBytes)
    {
        if (data == null || oldBytes == null || newBytes == null) return 0;
        if (oldBytes.Length == 0 || data.Length < oldBytes.Length) return 0;

        int count = 0;
        int limit = data.Length - oldBytes.Length;

        for (int i = 0; i <= limit; i++)
        {
            if (data[i] != oldBytes[0])
            {
                continue;
            }

            bool match = true;
            for (int j = 1; j < oldBytes.Length; j++)
            {
                if (data[i + j] != oldBytes[j])
                {
                    match = false;
                    break;
                }
            }

            if (match)
            {
                Buffer.BlockCopy(newBytes, 0, data, i, newBytes.Length);
                count++;
                i += oldBytes.Length - 1;
            }
        }

        return count;
    }
}
"@

function Kill-ChromeProcesses {
    Write-Host '[*] 競合回避のため、既存の Chrome プロセスを終了します...'
    try {
        Get-Process -Name chrome -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
    catch {
    }
}

function Main {
    try {
        Kill-ChromeProcesses

        $baseDir = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($baseDir)) {
            $baseDir = Split-Path -Parent $PSCommandPath
        }

        $searchPattern = Join-Path $baseDir 'App\Chrome-bin\*\chrome.dll'
        $dllPaths = Get-ChildItem -Path (Join-Path $baseDir 'App\Chrome-bin') -Recurse -Filter 'chrome.dll' -File -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName

        if (-not $dllPaths) {
            Write-Host '[ERROR] chrome.dll が見つかりません。'
            Write-Host ('探索パス: ' + $searchPattern)
            return
        }

        $patchTargets = @(
            @{ Target = 'SOFTWARE\Policies\Google\Chrome'; Dummy = 'SOFTWARE\Policies\Xoogle\Xhrome' },
            @{ Target = 'SOFTWARE\Policies\Google\Update'; Dummy = 'SOFTWARE\Policies\Xoogle\Uxdate' }
        )

        foreach ($targetDll in $dllPaths) {
            Write-Host ''
            Write-Host ('[*] ターゲット: ' + $targetDll)

            $fileData = [System.IO.File]::ReadAllBytes($targetDll)
            $isModified = $false

            foreach ($pair in $patchTargets) {
                $targetBytes = [System.Text.Encoding]::Unicode.GetBytes($pair.Target)
                $dummyBytes = [System.Text.Encoding]::Unicode.GetBytes($pair.Dummy)

                $targetCount = [ChromePatchHelper]::Replace($fileData, $targetBytes, $dummyBytes)

                if ($targetCount -gt 0) {
                    Write-Host ("  [+] '{0}' を {1} 箇所発見。パッチを適用します。" -f $pair.Target, $targetCount)
                    $isModified = $true
                }
                elseif ([ChromePatchHelper]::Count($fileData, $dummyBytes) -gt 0) {
                    Write-Host ("  [i] 既に '{0}' へパッチ適用済みです。" -f $pair.Dummy)
                }
                else {
                    Write-Host ("  [-] '{0}' が見つかりません。" -f $pair.Target)
                }
            }

            if ($isModified) {
                Write-Host '  [*] 変更を保存中...'
                [System.IO.File]::WriteAllBytes($targetDll, $fileData)
                Write-Host '  [+] パッチ適用完了。'
            }
            else {
                Write-Host '  [i] 変更の必要はありません。'
            }
        }

        Write-Host ''
        Write-Host '[+] すべての処理が完了しました。'

        $launcherCandidates = @(
            (Join-Path $baseDir 'GoogleChromePortable.exe'),
            (Join-Path $baseDir 'App\Chrome-bin\chrome.exe')
        )

        $launcherFound = $false
        foreach ($launcher in $launcherCandidates) {
            if (Test-Path -LiteralPath $launcher) {
                Write-Host ('[*] 起動します: ' + $launcher)
                Start-Process -FilePath $launcher -WorkingDirectory $baseDir
                $launcherFound = $true
                break
            }
        }

        if (-not $launcherFound) {
            Write-Host '[WARN] 起動可能な実行ファイルが見つかりません。'
        }
    }
    catch {
        Write-Host ''
        Write-Host '[FATAL ERROR] 処理中にエラーが発生しました:'
        Write-Host $_.Exception.ToString()
        if ($_.ScriptStackTrace) {
            Write-Host $_.ScriptStackTrace
        }
    }
}

Main
Write-Host ''
Write-Host ('-' * 40)
Read-Host 'Enter キーを押して終了してください...'
