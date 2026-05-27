$ErrorActionPreference = 'Continue'

# Reverts the DACL/MIL lock applied by Run.ps1 and re-applies organization GPO.
#
# Run.ps1 empties each policy key, applies DENY ACEs (SYSTEM for HKLM, plus the
# current user SID for HKCU) and a Mandatory Integrity Label High/NoWriteUp.
# Those DENY ACEs would also block our own elevated token from a plain
# Remove-Item, so we enable SeTakeOwnership/SeRestore and reset the DACL before
# deleting. After deletion, gpupdate /force lets gpsvc recreate the keys with
# the org's intended values.

if (-not ('Win32.PrivAdj' -as [type])) {
    Add-Type -Namespace Win32 -Name PrivAdj -MemberDefinition @'
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
public static bool Enable(string priv) {
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
    [void][Win32.PrivAdj]::Enable($p)
}

$adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')

function Reset-KeyAcl {
    param([string]$KeyPath)
    try { $acl = Get-Acl -Path $KeyPath -ErrorAction Stop } catch { return }
    try {
        $acl.SetOwner($adminSid)
        Set-Acl -Path $KeyPath -AclObject $acl -ErrorAction Stop
    } catch {}
    try {
        $acl = Get-Acl -Path $KeyPath
        foreach ($r in @($acl.Access)) { [void]$acl.RemoveAccessRule($r) }
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
    if (-not (Test-Path $KeyPath)) { return $false }
    try { Remove-Item -Path $KeyPath -Recurse -Force -ErrorAction Stop; return $true } catch {}
    $stack = New-Object System.Collections.Generic.Stack[string]
    $order = New-Object System.Collections.Generic.List[string]
    $stack.Push($KeyPath)
    while ($stack.Count -gt 0) {
        $k = $stack.Pop()
        $order.Add($k)
        Get-ChildItem -Path $k -ErrorAction SilentlyContinue | ForEach-Object { $stack.Push($_.PSPath) }
    }
    for ($i = $order.Count - 1; $i -ge 0; $i--) { Reset-KeyAcl -KeyPath $order[$i] }
    Remove-Item -Path $KeyPath -Recurse -Force -ErrorAction SilentlyContinue
    return -not (Test-Path $KeyPath)
}

# Mirror of Run.ps1's lock targets — clean the same set so nothing is left
# locked when restoring org policy.
$policyKeys = @(
    'HKLM:\Software\Policies\Google\Chrome',
    'HKLM:\Software\WOW6432Node\Policies\Google\Chrome',
    'HKLM:\Software\Policies\Google\CloudManagement',
    'HKLM:\Software\Google\Enrollment',
    'HKLM:\Software\Policies\Chromium',
    'HKLM:\Software\WOW6432Node\Policies\Chromium',
    'HKCU:\Software\Policies\Google\Chrome',
    'HKCU:\Software\Policies\Chromium'
)

foreach ($k in $policyKeys) {
    if (Test-Path $k) {
        if (Force-DeleteKey -KeyPath $k) {
            Write-Host "[STATUS] Deleted locked key: $k"
        } else {
            Write-Host "[WARN] Could not fully delete: $k" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[STATUS] Not present (nothing to do): $k"
    }

    $bak = $k + '.bak'
    if (Test-Path $bak) {
        Remove-Item -Path $bak -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[STATUS] Cleaned legacy backup: $bak"
    }
}

Write-Host ''
Write-Host '[STATUS] Forcing GPO refresh so the organization policies repopulate...'
& gpupdate.exe /force

Write-Host ''
Write-Host '[INFO] Done. Org-managed Chrome policies should now be back in effect.'
Read-Host 'Press Enter to close'
