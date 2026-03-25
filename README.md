# 🔧 Windows Patch Automation (Friday After Patch Tuesday)

**Fully automated patching workflow for Windows Server with controlled installation, reboot logic, and monitoring integration**

This project provides a **self-contained patch orchestration system for Windows Server**, designed for environments where patching must occur on tightly controlled schedules — with full observability, safe‑guards, and zero-risk automation loops.

The solution consists of:

*   One **installer script** (`Install-PatchAutomation.ps1`)
*   Two **worker scripts** placed on the server:
    *   `Patch-WindowsUpdate.ps1`
    *   `Reboot-IfRequired.ps1`
*   Three **Scheduled Tasks** created automatically

All components run under **SYSTEM**, and no external dependencies are required.

***

## 🚀 Key Features

### 🗓 Smart scheduling (Patch Tuesday logic built-in)

The scripts automatically compute:

*   **Patch Tuesday** (2nd Tuesday of each month)
*   **Friday after Patch Tuesday**
*   **Saturday after Patch Tuesday**

These dates are enforced **at runtime**, regardless of when the scheduled tasks technically fire.  
This ensures patching always happens at the intended time, even across calendar variations.

### 🔒 Safe patch installation

The Friday patch job:

*   Searches for updates (excluding *Preview* patches)
*   Downloads quietly
*   Installs silently
*   **Never automatically reboots**
*   Writes logs to `C:\Logs`
*   Reports detailed state + errors to Windows Event Log

If a **pending reboot** exists before installation, the job is **deferred** and a retry is automatically prepared.

### 🔄 Controlled reboot automation (Saturday)

The Saturday reboot script:

*   Verifies it *really is* the Saturday after Patch Tuesday
*   Checks for a pending reboot
*   If required → schedules restart in 60 seconds
*   If not → no action taken
*   Safely enables a retry task if post‑reboot patching is needed

### 🧠 Intelligent retry system

If installation on Friday cannot proceed (pending reboot, or other safe‑guard triggers), the script activates a **retry mode**:

*   The retry task runs **at startup**
*   It continues the patch workflow
*   It automatically disables itself when finished
*   Loop-prevention guarantees retries cannot get stuck

### 📋 Optional dry run mode (`-DryRun`)

Great for auditing, SIEM integration, and compliance checks.

`Patch-WindowsUpdate.ps1 -DryRun` will:

*   Enforce the exact patch window
*   Search for updates only
*   Log all applicable updates
*   Produce detailed Event Log entries
*   Perform **zero installations**

This can be invoked manually or triggered via installer option `-RunDryRunNow`.

### 📊 Full Event Log visibility

All actions emit structured Windows Event Log entries under:

    Log: Application  
    Source: PatchAutomation

Event IDs cover:

*   Lifecycle (4100–4120)
*   DryRun diagnostics (4105–4107)
*   Window enforcement (4510)
*   Retry logic (4201–4202)
*   Errors (4501–4503)
*   Reboot workflow (5200–5203)

This makes it easy to integrate with:

*   Veeam ONE
*   Grafana/Prometheus
*   Splunk / Elastic
*   SCOM
*   Sentinel

***

## 🧩 Components Installed

### PowerShell Scripts

| Script                      | Purpose                                                                                                                                                                |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Patch-WindowsUpdate.ps1** | Performs patch search/download/install or DryRun. Enforces Friday-after-Patch-Tuesday. Handles retry mode, logging, EventLog, state tracking, and COM Installer logic. |
| **Reboot-IfRequired.ps1**   | Runs Saturday morning. Checks reboot necessity and performs scheduled restart safely.                                                                                  |

### Scheduled Tasks

| Task Name                           | Schedule                | Action                                                                             |
| ----------------------------------- | ----------------------- | ---------------------------------------------------------------------------------- |
| **Monthly Windows Update**          | Weekly Friday @ 22:00   | Runs patch script (normal mode). Script self-validates the correct monthly window. |
| **Conditional Server Reboot**       | Weekly Saturday @ 05:00 | Runs reboot script. Only reboots if required *and* within patch window.            |
| **PostReboot Windows Update Retry** | At system startup       | Disabled by default; enabled automatically for stateful retry scenarios.           |

***

## 📁 Folder Structure

    C:\Scripts
     ├── Patch-WindowsUpdate.ps1
     ├── Reboot-IfRequired.ps1
     └── PatchState.json  (runtime state)

    C:\Logs
     ├── WindowsUpdate_YYYY-MM-DD.log
     └── RebootCheck_YYYY-MM-DD.log

***

## 🛡️ Design Priorities

*   **Predictability**  
    Patching *always* happens the Friday after Patch Tuesday — never earlier/later.

*   **Safety**  
    No automatic reboots except in the controlled Saturday window.

*   **Transparency**  
    Extensive logging and Event Log entries provide full visibility.

*   **Self-healing**  
    Retry logic avoids patching failures caused by pending reboot states.

*   **Idempotency**  
    Installer updates scripts without breaking custom schedules.

*   **Zero external dependencies**  
    Everything is pure PowerShell + built‑in Windows Update COM API.

***

## ▶️ How to Install

```powershell
# Run with administrator privileges
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-PatchAutomation.ps1
```

### Optional flags

| Flag              | Description                                          |
| ----------------- | ---------------------------------------------------- |
| **-RunDryRunNow** | Immediately runs DryRun mode after installation      |
| **-InstallNow**   | Immediately runs real patch installation (no reboot) |

***

## 📦 Ideal Use Cases

*   Production servers with **strict patch windows**
*   Environments requiring **manual reboot separation**
*   Servers outside domain / without WSUS / without SCCM
*   Organizations needing **transparent and auditable** patch workflows
*   Enterprises where reboots must happen at **a specific time only**

***

## 📝 Conclusion

This system transforms Windows patching into:

*   a **predictable**
*   **auditable**
*   **fault‑tolerant**
*   **secure**
*   **maintenance‑friendly**

automation pipeline that fits enterprise operational requirements.
