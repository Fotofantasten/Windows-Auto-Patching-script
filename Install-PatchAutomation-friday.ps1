<#
.SYNOPSIS
  Installs server patch automation:
  - Creates C:\Scripts and C:\Logs
  - Writes Patch-WindowsUpdate.ps1 (install updates silently, no auto-reboot)
  - Writes Reboot-IfRequired.ps1   (reboot only if required, controlled window)
  - Creates three Scheduled Tasks (SYSTEM):
      * "Monthly Windows Update"      → WEEKLY FRI 22:00
      * "Conditional Server Reboot"   → WEEKLY SAT 05:00
      * "PostReboot Windows Update Retry" → ONSTART (disabled by default)
  - The worker scripts self-enforce the **Friday/Saturday after Patch Tuesday** window.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ScriptRoot = 'C:\Scripts',
    [string]$LogRoot    = 'C:\Logs',
    [string]$PatchTime  = '22:00',  # 24h format
    [string]$RebootTime = '05:00'   # 24h format
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Ensure directories -------------------------------------------------------
foreach($p in @($ScriptRoot, $LogRoot)) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# --- Paths -------------------------------------------------------------------
$PatchScriptPath  = Join-Path $ScriptRoot 'Patch-WindowsUpdate.ps1'
$RebootScriptPath = Join-Path $ScriptRoot 'Reboot-IfRequired.ps1'

# --- Helper: write file only if changed --------------------------------------
function Write-FileSafe {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Content
    )
    $needsWrite = $true
    if (Test-Path $Path) {
        $existing = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
        if ($existing -eq $Content) { $needsWrite = $false }
    }
    if ($needsWrite) { $Content | Out-File -FilePath $Path -Encoding UTF8 -Force }
}

# --- Worker: Patch-WindowsUpdate.ps1 (EN) ------------------------------------
$PatchScript = @'
[CmdletBinding()]
param(
    [switch]$Retry,
    [string]$LogDir = "C:\Logs",
    [string]$StatePath = "C:\Scripts\PatchState.json",
    [string]$EventLogName = "Application",
    [string]$EventSource = "PatchAutomation",
    [string]$RetryTaskName = "PostReboot Windows Update Retry",
    [int]$RetentionDays = 90
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -----------------------
# Logging & event helpers
# -----------------------
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir ("WindowsUpdate_{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts $Message" | Out-File -Append -FilePath $LogFile -Encoding utf8
}

function Ensure-EventSource {
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName $EventLogName -Source $EventSource
        }
    } catch {
        Write-Log "WARN: Could not ensure EventLog source '$EventSource'. $_"
    }
}

function Write-Event {
    param(
        [ValidateSet("Information","Warning","Error")] [string]$EntryType,
        [int]$EventId,
        [string]$Message
    )
    try {
        Ensure-EventSource
        if ([System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $EntryType -EventId $EventId -Message $Message
        } else {
            Write-Log "WARN: Event source not available. EventId=$EventId Type=$EntryType Msg=$Message"
        }
    } catch {
        Write-Log "WARN: Failed writing to EventLog. EventId=$EventId Type=$EntryType. $_"
    }
}

# -----------------------
# State helpers (JSON)
# -----------------------
function Load-State { if (Test-Path $StatePath) { try { Get-Content $StatePath -Raw | ConvertFrom-Json } catch { $null } } else { $null } }
function Save-State([object]$obj) { $obj | ConvertTo-Json -Depth 5 | Out-File -FilePath $StatePath -Encoding utf8 -Force }
function Clear-State { if (Test-Path $StatePath) { Remove-Item $StatePath -Force } }
function Set-RetryTaskEnabled([bool]$Enable) {
    $mode = if ($Enable) { "/ENABLE" } else { "/DISABLE" }
    try { & schtasks.exe /Change /TN "$RetryTaskName" $mode | Out-Null; Write-Log "Retry task '$RetryTaskName' set to: $mode" }
    catch { Write-Log "WARN: Failed to change retry task state. $_" }
}

# ---------------------------------------------------------
