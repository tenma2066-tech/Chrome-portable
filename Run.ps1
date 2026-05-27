param([string]$Mode = 'launch')
if (-not $Mode) { $Mode = 'launch' }

$ErrorActionPreference = 'Continue'

# Some cmd-launched Windows PowerShell sessions can fail to autoload
# Microsoft.PowerShell.Security because ObjectSecurity type data is already
# present. Get-Acl/Set-Acl are required for registry DACL work, so load it
# deterministically before touching the registry.
Remove-TypeData -TypeName System.Security.AccessControl.ObjectSecurity -ErrorAction SilentlyContinue
try {
    Import-Module Microsoft.PowerShell.Security -ErrorAction Stop
} catch {
    Write-Warning "Failed to load Microsoft.PowerShell.Security: $_"
}

$portableDir = $PSScriptRoot
if (-not $portableDir.EndsWith('\')) { $portableDir += '\' }
$exe = Join-Path $portableDir 'GoogleChromePortable.exe'

if (-not (Test-Path $exe)) {
    Write-Host "[ERROR] Launcher not found: $exe" -ForegroundColor Red
    Read-Host 'Press Enter to exit'
    exit 1
}

# --- P/Invoke layer -----------------------------------------------------------
if (-not ('Win32.RegSec' -as [type])) {
    Add-Type -Namespace Win32 -Name RegSec -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, Pack=1)]
public struct TokPriv1Luid { public int Count; public long Luid; public int Attr; }
[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool OpenProcessToken(IntPtr h, int acc, out IntPtr phtok);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
[DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
[DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
[DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern int RegOpenKeyExW(IntPtr hKey, string lpSubKey, int ulOptions, int samDesired, out IntPtr phkResult);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegCloseKey(IntPtr hKey);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegSetKeySecurity(IntPtr hKey, int SecurityInformation, byte[] pSecurityDescriptor);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegGetKeySecurity(IntPtr hKey, int SecurityInformation, byte[] pSecurityDescriptor, ref int lpcbSecurityDescriptor);
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
public const int LABEL_SECURITY_INFORMATION = 0x00000010;
public const int ACCESS_SYSTEM_SECURITY     = 0x01000000;
public const int WRITE_OWNER                = 0x00080000;
public const int WRITE_DAC                  = 0x00040000;
public const int READ_CONTROL               = 0x00020000;
public static IntPtr HKLM = new IntPtr(unchecked((int)0x80000002));
public static IntPtr HKCU = new IntPtr(unchecked((int)0x80000001));
public static bool EnablePriv(string priv) {
    IntPtr htok;
    if (!OpenProcessToken(GetCurrentProcess(), 0x28, out htok)) return false;
    TokPriv1Luid tp = new TokPriv1Luid();
    tp.Count = 1; tp.Attr = 0x2;
    if (!LookupPrivilegeValue(null, priv, ref tp.Luid)) { CloseHandle(htok); return false; }
    bool ok = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    CloseHandle(htok);
    return ok;
}
'@
}
foreach ($p in 'SeTakeOwnershipPrivilege','SeRestorePrivilege','SeBackupPrivilege','SeSecurityPrivilege') {
    [void][Win32.RegSec]::EnablePriv($p)
}

# --- Functions ----------------------------------------------------------------

function Stop-PortableProc {
    param([string]$FilterName, [string]$BasePath)
    $found = Get-CimInstance Win32_Process -Filter "Name='$FilterName'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($BasePath, [System.StringComparison]::OrdinalIgnoreCase) }
    $ids = @()
    foreach ($t in $found) {
        $ids += $t.ProcessId
        $proc = Get-Process -Id $t.ProcessId -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host ("  - requesting close: $FilterName PID {0}" -f $t.ProcessId)
            $proc.CloseMainWindow() | Out-Null
        }
    }
    return $ids
}

function Backup-Profile {
    Write-Host '[STATUS] Checking if profile backup is needed...'
    # Only backup if Chrome is currently running (ensure data is fresh/clean state)
    $running = Get-Process -Name 'chrome' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($portableDir, [System.StringComparison]::OrdinalIgnoreCase) }
    
    if (-not $running) {
        Write-Host '  - skipping backup (portable Chrome not running).'
        return
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupRoot = Join-Path $portableDir 'Data\backup'
    $destDir = Join-Path $backupRoot $stamp
    
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    
    $profileData = Join-Path $portableDir 'Data\profile'
    $defaultDir  = Join-Path $profileData 'Default'
    
    $filesToCopy = @(
        @{ Src = Join-Path $defaultDir 'Bookmarks';          Dest = Join-Path $destDir 'Bookmarks' },
        @{ Src = Join-Path $defaultDir 'Preferences';        Dest = Join-Path $destDir 'Preferences' },
        @{ Src = Join-Path $defaultDir 'Secure Preferences'; Dest = Join-Path $destDir 'Secure Preferences' },
        @{ Src = Join-Path $defaultDir 'Login Data';         Dest = Join-Path $destDir 'Login Data' },
        @{ Src = Join-Path $profileData 'Local State';       Dest = Join-Path $destDir 'Local State' }
    )

    Write-Host "[STATUS] Backing up profile files to $stamp..."
    foreach ($f in $filesToCopy) {
        if (Test-Path $f.Src) {
            try {
                Copy-Item -Path $f.Src -Destination $f.Dest -Force -ErrorAction Stop
            } catch {
                Write-Warning "Failed to copy $($f.Src): $_"
            }
        }
    }

    # Prune old backups (keep last 5)
    $dirs = Get-ChildItem -Path $backupRoot -Directory | Sort-Object Name -Descending
    if ($dirs.Count -gt 5) {
        $dirs | Select-Object -Skip 5 | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  - pruned $(( $dirs.Count - 5 )) old backup(s)."
    }
}

function Repair-ExitType {
    $prefFile = Join-Path $portableDir 'Data\profile\Default\Preferences'
    if (-not (Test-Path $prefFile)) { return }
    
    Write-Host '[STATUS] Checking profile exit state...'
    try {
        $jsonStr = [System.IO.File]::ReadAllText($prefFile, [System.Text.Encoding]::UTF8)
        $pref = $jsonStr | ConvertFrom-Json
        
        $dirty = $false
        if ($pref.profile.exit_type -ne 'Normal') {
            $pref.profile.exit_type = 'Normal'
            $dirty = $true
        }
        if ($pref.profile.exited_cleanly -ne $true) {
            $pref.profile.exited_cleanly = $true
            $dirty = $true
        }
        
        if ($dirty) {
            Write-Host '  - profile was marked as crashed; repairing exit_type to "Normal"...'
            # CRITICAL: -Depth 100 is mandatory to prevent truncation of nested objects.
            $newJson = $pref | ConvertTo-Json -Depth 100
            [System.IO.File]::WriteAllText($prefFile, $newJson, (New-Object System.Text.UTF8Encoding($false)))
        } else {
            Write-Host '  - profile exit state is clean.'
        }
    } catch {
        Write-Warning "Failed to repair Preferences file: $_"
    }
}

function Start-PolicyWatcher {
    param([string]$PortableDir, [string]$UserSid)
    $script = Join-Path $PortableDir 'Watcher.ps1'
    if (-not (Test-Path $script)) { return }
    
    Start-Process powershell.exe -WindowStyle Hidden `
        -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',
                      "`"$script`"",' -PortableDir',"`"$PortableDir`"",
                      '-UserSid',$UserSid
    Write-Host '[STATUS] Policy watcher started (background).'
}

# --- Shared setup -------------------------------------------------------------

$currentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$systemSid      = 'S-1-5-18'
$adminSid       = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')

$lockTargets = @(
    @{ Key = 'HKLM:\Software\Policies\Google\Chrome';                      DenySids = @($systemSid) },
    @{ Key = 'HKLM:\Software\WOW6432Node\Policies\Google\Chrome';          DenySids = @($systemSid) },
    @{ Key = 'HKLM:\Software\Policies\Google\CloudManagement';             DenySids = @($systemSid) },
    @{ Key = 'HKLM:\Software\Google\Enrollment';                           DenySids = @($systemSid) },
    @{ Key = 'HKLM:\Software\Policies\Chromium';                           DenySids = @($systemSid) },
    @{ Key = 'HKLM:\Software\WOW6432Node\Policies\Chromium';               DenySids = @($systemSid) },
    @{ Key = 'HKCU:\Software\Policies\Google\Chrome';                      DenySids = @($systemSid, $currentUserSid) },
    @{ Key = 'HKCU:\Software\Policies\Chromium';                           DenySids = @($systemSid, $currentUserSid) }
)

function Reset-KeyAcl {
    param([string]$KeyPath)
    if (-not (Test-Path $KeyPath)) { return }
    # 1. Take ownership regardless of current access.
    # We use a fresh RegistrySecurity object to avoid needing to Read the current one first.
    try {
        $ownerAcl = New-Object System.Security.AccessControl.RegistrySecurity
        $ownerAcl.SetOwner($adminSid)
        Set-Acl -Path $KeyPath -AclObject $ownerAcl -ErrorAction Stop
    } catch {
        Write-Host "[WARN] SetOwner failed on ${KeyPath}: $_" -ForegroundColor Yellow
    }

    # 2. Now that we (Admins) are owners, we have WRITE_DAC. Reset the DACL.
    try {
        $acl = New-Object System.Security.AccessControl.RegistrySecurity
        $acl.SetAccessRuleProtection($true, $false) # Disable inheritance, remove existing
        $allow = New-Object System.Security.AccessControl.RegistryAccessRule(
            $adminSid,
            [System.Security.AccessControl.RegistryRights]'FullControl',
            [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
            [System.Security.AccessControl.PropagationFlags]'None',
            [System.Security.AccessControl.AccessControlType]'Allow'
        )
        $acl.AddAccessRule($allow)
        Set-Acl -Path $KeyPath -AclObject $acl -ErrorAction Stop
    } catch {
        Write-Host "[WARN] DACL reset failed on ${KeyPath}: $_" -ForegroundColor Yellow
    }
}

function Force-DeleteKey {
    param([string]$KeyPath)
    if (-not (Test-Path $KeyPath)) { return }
    try { Remove-Item -Path $KeyPath -Recurse -Force -ErrorAction Stop; return } catch {
        Write-Host "[STATUS] Direct delete blocked, taking ownership of $KeyPath..."
    }
    # If the key is locked, we can't enumerate subkeys via Get-ChildItem.
    # We reset the root key ACL first, then try to enumerate/delete.
    Reset-KeyAcl -KeyPath $KeyPath
    if (Test-Path $KeyPath) {
        Remove-Item -Path $KeyPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Apply-MandatoryHighNoWriteUp {
    param([string]$KeyPath)
    $root = $null; $sub = $null
    if     ($KeyPath.StartsWith('HKLM:', [System.StringComparison]::OrdinalIgnoreCase)) { $root = [Win32.RegSec]::HKLM; $sub = $KeyPath.Substring(5).TrimStart('\') }
    elseif ($KeyPath.StartsWith('HKCU:', [System.StringComparison]::OrdinalIgnoreCase)) { $root = [Win32.RegSec]::HKCU; $sub = $KeyPath.Substring(5).TrimStart('\') }
    else { return }
    $samDesired = [Win32.RegSec]::ACCESS_SYSTEM_SECURITY -bor [Win32.RegSec]::WRITE_OWNER -bor [Win32.RegSec]::WRITE_DAC -bor [Win32.RegSec]::READ_CONTROL
    $hkey = [IntPtr]::Zero
    $rc = [Win32.RegSec]::RegOpenKeyExW($root, $sub, 0, $samDesired, [ref]$hkey)
    if ($rc -ne 0) { return }
    try {
        $sddl = 'O:BAG:BAD:S:(ML;OICI;NW;;;HI)'
        $rsd  = New-Object System.Security.AccessControl.RawSecurityDescriptor($sddl)
        $bytes = New-Object byte[] $rsd.BinaryLength
        $rsd.GetBinaryForm($bytes, 0)
        [void][Win32.RegSec]::RegSetKeySecurity($hkey, [Win32.RegSec]::LABEL_SECURITY_INFORMATION, $bytes)
    } finally {
        [void][Win32.RegSec]::RegCloseKey($hkey)
    }
}

function Test-PolicyKeyCompliant {
    param([string]$KeyPath, [string[]]$DenySids)
    if (-not (Test-Path $KeyPath)) { return $false }

    try {
        $item = Get-Item $KeyPath -ErrorAction Stop
        $valCount = $item.GetValueNames().Count
        $subCount = (Get-ChildItem $KeyPath -ErrorAction SilentlyContinue).Count
        $denySidsFound = @((Get-Acl $KeyPath -ErrorAction Stop).Access |
            Where-Object { $_.AccessControlType -eq 'Deny' } |
            ForEach-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value })

        foreach ($sid in $DenySids) {
            if ($denySidsFound -notcontains $sid) { return $false }
        }
        return ($valCount -eq 0 -and $subCount -eq 0)
    } catch {
        return $false
    }
}

function Lock-PolicyKey {
    param([string]$KeyPath, [string[]]$DenySids)
    try {
        if (Test-PolicyKeyCompliant -KeyPath $KeyPath -DenySids $DenySids) {
            Write-Host "[STATUS] Already locked: $KeyPath"
            return
        }

        if (-not (Test-Path $KeyPath)) {
            New-Item -Path $KeyPath -Force -ErrorAction Stop | Out-Null
        }

        $isUserHive = $KeyPath.StartsWith('HKCU:', [System.StringComparison]::OrdinalIgnoreCase)
        if ($isUserHive) {
            $acl = Get-Acl -Path $KeyPath -ErrorAction Stop
            $acl.SetAccessRuleProtection($true, $true)
            $rights = [System.Security.AccessControl.RegistryRights]'SetValue, CreateSubKey, Delete, ChangePermissions, TakeOwnership'
            foreach ($sidStr in $DenySids) {
                $sid = New-Object System.Security.Principal.SecurityIdentifier($sidStr)
                $denyRule = New-Object System.Security.AccessControl.RegistryAccessRule(
                    $sid, $rights,
                    [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
                    [System.Security.AccessControl.PropagationFlags]'None',
                    [System.Security.AccessControl.AccessControlType]'Deny'
                )
                $acl.AddAccessRule($denyRule)
            }
            Set-Acl -Path $KeyPath -AclObject $acl -ErrorAction Stop
            Write-Host "[STATUS] Locked: $KeyPath  (DENY: $($DenySids -join ', '))"
            Apply-MandatoryHighNoWriteUp -KeyPath $KeyPath
            return
        }

        Force-DeleteKey -KeyPath $KeyPath
        New-Item -Path $KeyPath -Force -ErrorAction Stop | Out-Null
        $acl = Get-Acl -Path $KeyPath -ErrorAction Stop
        $acl.SetAccessRuleProtection($true, $true)
        $rights = [System.Security.AccessControl.RegistryRights]'SetValue, CreateSubKey, Delete, ChangePermissions, TakeOwnership'
        foreach ($sidStr in $DenySids) {
            $sid = New-Object System.Security.Principal.SecurityIdentifier($sidStr)
            $denyRule = New-Object System.Security.AccessControl.RegistryAccessRule(
                $sid, $rights,
                [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
                [System.Security.AccessControl.PropagationFlags]'None',
                [System.Security.AccessControl.AccessControlType]'Deny'
            )
            $acl.AddAccessRule($denyRule)
        }
        Set-Acl -Path $KeyPath -AclObject $acl -ErrorAction Stop
        Write-Host "[STATUS] Locked: $KeyPath  (DENY: $($DenySids -join ', '))"
        Apply-MandatoryHighNoWriteUp -KeyPath $KeyPath
    } catch {
        Write-Host "[WARN] Could not lock ${KeyPath}: $_" -ForegroundColor Yellow
    }
}

# --- Execution gates ----------------------------------------------------------

if ($Mode -eq 'launch') {
    Backup-Profile
    
    Write-Host '[STATUS] Stopping stale portable Chrome processes...'
    $gcpPids    = @(Stop-PortableProc 'GoogleChromePortable.exe' $portableDir)
    $chromePids = @(Stop-PortableProc 'chrome.exe'               $portableDir)
    $allPids    = @($gcpPids + $chromePids | Where-Object { $null -ne $_ -and $_ -ne '' })

    if ($allPids.Count -gt 0) {
        Write-Host '[STATUS] Waiting up to 8 s for graceful exit...'
        $deadline = [datetime]::Now.AddSeconds(8)
        while ([datetime]::Now -lt $deadline) {
        $alive = $allPids | Where-Object {
            $processId = $_
            $processId -and (Get-Process -Id $processId -ErrorAction SilentlyContinue)
        }
            if (-not $alive) { break }
            Start-Sleep -Milliseconds 500
        }
        foreach ($id in $allPids) {
            if ($id -and (Get-Process -Id $id -ErrorAction SilentlyContinue)) {
                Write-Host ("  - force kill PID {0} (did not exit in time)" -f $id) -ForegroundColor Yellow
                Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
            }
        }
        Start-Sleep -Milliseconds 800
    }

    $profileDir = Join-Path $portableDir 'Data\profile'
    $lockFile   = Join-Path $profileDir 'lockfile'
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        Write-Host '[STATUS] Removed stale profile lockfile.'
    }
    
    Repair-ExitType
}

if ($Mode -ne 'status') {
    foreach ($t in $lockTargets) {
        $bak = $t.Key + '.bak'
        if (Test-Path $bak) { Remove-Item -Path $bak -Recurse -Force -ErrorAction SilentlyContinue }
    }
    foreach ($t in $lockTargets) {
        Lock-PolicyKey -KeyPath $t.Key -DenySids $t.DenySids
    }
}

# --- Verification pass --------------------------------------------------------
Write-Host ''
Write-Host '[VERIFY] Checking enforcement state (Access Denied means the lock is working):'
foreach ($t in $lockTargets) {
    if (-not (Test-Path $t.Key)) { Write-Host "  MISSING $($t.Key)" -ForegroundColor Yellow; continue }
    
    $tag = '???'
    $valCount = '?'
    $sub = '?'
    $denyCount = '?'

    try {
        $valCount = (Get-Item $t.Key -ErrorAction Stop).GetValueNames().Count
        $sub      = (Get-ChildItem $t.Key -ErrorAction SilentlyContinue).Count
        $denyCount = ((Get-Acl $t.Key -ErrorAction Stop).Access | Where-Object { $_.AccessControlType -eq 'Deny' }).Count
        $tag = if ($valCount -eq 0 -and $sub -eq 0 -and $denyCount -ge $t.DenySids.Count) { 'OK ' } else { 'BAD' }
    } catch {
        if ($_.Exception.Message -like "*Access is denied*") {
            $tag = 'OK '
            $denyCount = 'LOCKED'
        } else {
            $tag = 'BAD'
            $denyCount = 'ERR'
        }
    }
    Write-Host ("  [$tag] {0,-58} values={1} subs={2} denyACEs={3}" -f $t.Key, $valCount, $sub, $denyCount)
}

if ($Mode -eq 'status' -or $Mode -eq 'lock') {
    exit 0
}

# --- Launch -------------------------------------------------------------------
Write-Host ''
Write-Host '[STATUS] Launching Portable Chrome (de-escalated to Medium IL)...'
$shell = New-Object -ComObject Shell.Application
$shell.ShellExecute($exe, '', (Split-Path $exe -Parent), 'open', 1)

Start-PolicyWatcher -PortableDir $portableDir -UserSid $currentUserSid

Write-Host ''
Write-Host '[INFO] HKLM keys: write-blocked for SYSTEM (machine GPO refresh).'
Write-Host '[INFO] HKCU keys: write-blocked for SYSTEM and current user (user GPO refresh).'
Write-Host '[INFO] Mandatory Integrity Label = High/NoWriteUp adds an IL barrier on top.'
Write-Host '[INFO] Chrome launched at Medium IL via Shell.Application (de-escalated).'

# --- Console auto-close -------------------------------------------------------
$deadline = [datetime]::Now.AddSeconds(3)
$found = $false
while ([datetime]::Now -lt $deadline) {
    if (Get-Process -Name 'chrome' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($portableDir, [System.StringComparison]::OrdinalIgnoreCase) }) {
        $found = $true
        break
    }
    Start-Sleep -Milliseconds 300
}

if ($found) {
    $hwnd = [Win32.RegSec]::GetConsoleWindow()
    if ($hwnd -ne [IntPtr]::Zero) {
        Write-Host '[STATUS] Chrome detected. Hiding console in 1s...'
        Start-Sleep -Seconds 1
        [void][Win32.RegSec]::ShowWindow($hwnd, 0) # SW_HIDE = 0
    }
} else {
    Write-Warning 'Portable Chrome did not appear within 3s. Console will remain visible.'
}
