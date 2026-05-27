param([string]$PortableDir, [string]$UserSid)

$ErrorActionPreference = 'Stop'

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

$systemSid = 'S-1-5-18'
$adminSid  = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')

$lockTargets = @(
    @{ Key = 'HKLM:\Software\Policies\Google\Chrome';                      DenySids = @($systemSid) },
    @{ Key = 'HKLM:\Software\WOW6432Node\Policies\Google\Chrome';          DenySids = @($systemSid) },
    @{ Key = 'HKLM:\Software\Policies\Google\CloudManagement';             DenySids = @($systemSid) },
    @{ Key = 'HKLM:\Software\Google\Enrollment';                           DenySids = @($systemSid) },
    @{ Key = 'HKLM:\Software\Policies\Chromium';                           DenySids = @($systemSid) },
    @{ Key = 'HKLM:\Software\WOW6432Node\Policies\Chromium';               DenySids = @($systemSid) },
    @{ Key = 'HKCU:\Software\Policies\Google\Chrome';                      DenySids = @($systemSid, $UserSid) },
    @{ Key = 'HKCU:\Software\Policies\Chromium';                           DenySids = @($systemSid, $UserSid) }
)

function Reset-KeyAcl {
    param([string]$KeyPath)
    try {
        $ownerAcl = New-Object System.Security.AccessControl.RegistrySecurity
        $ownerAcl.SetOwner($adminSid)
        Set-Acl -Path $KeyPath -AclObject $ownerAcl -ErrorAction Stop
    } catch {}
    try {
        $acl = New-Object System.Security.AccessControl.RegistrySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $allow = New-Object System.Security.AccessControl.RegistryAccessRule(
            $adminSid,
            [System.Security.AccessControl.RegistryRights]'FullControl',
            [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
            [System.Security.AccessControl.PropagationFlags]'None',
            [System.Security.AccessControl.AccessControlType]'Allow'
        )
        $acl.AddAccessRule($allow)
        Set-Acl -Path $KeyPath -AclObject $acl -ErrorAction Stop
    } catch {}
}

function Force-DeleteKey {
    param([string]$KeyPath)
    if (-not (Test-Path $KeyPath)) { return }
    try { Remove-Item -Path $KeyPath -Recurse -Force -ErrorAction Stop; return } catch {}
    Reset-KeyAcl -KeyPath $KeyPath
    Remove-Item -Path $KeyPath -Recurse -Force -ErrorAction SilentlyContinue
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

function Lock-PolicyKey {
    param([string]$KeyPath, [string[]]$DenySids)
    try {
        Force-DeleteKey -KeyPath $KeyPath
        New-Item -Path $KeyPath -Force | Out-Null
        $acl = Get-Acl -Path $KeyPath
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
        Set-Acl -Path $KeyPath -AclObject $acl
        Apply-MandatoryHighNoWriteUp -KeyPath $KeyPath
    } catch {}
}

function Show-BalloonTip {
    param([string]$Title, [string]$Text)
    Add-Type -AssemblyName System.Windows.Forms
    $icon = New-Object System.Windows.Forms.NotifyIcon
    $icon.Icon = [System.Drawing.SystemIcons]::Shield
    $icon.Visible = $true
    $icon.ShowBalloonTip(5000, $Title, $Text, [System.Windows.Forms.ToolTipIcon]::Warning)
    Start-Sleep -Seconds 5
    $icon.Dispose()
}

# --- Main loop ----------------------------------------------------------------
while ($true) {
    # Exit if portable Chrome is no longer running.
    $running = Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($PortableDir, [System.StringComparison]::OrdinalIgnoreCase) }
    if (-not $running) { break }

    # Check each lock target.
    $violation = $false
    foreach ($t in $lockTargets) {
        if (-not (Test-Path $t.Key)) {
            $violation = $true
        } else {
            $valCount = (Get-Item $t.Key).GetValueNames().Count
            $subCount = (Get-ChildItem $t.Key -ErrorAction SilentlyContinue).Count
            if ($valCount -gt 0 -or $subCount -gt 0) {
                $violation = $true
            }
        }

        if ($violation) {
            Lock-PolicyKey -KeyPath $t.Key -DenySids $t.DenySids
            Show-BalloonTip 'Policy Watcher' "Re-locked tampered policy key: $($t.Key)"
            $violation = $false
        }
    }

    Start-Sleep -Seconds 90
}
