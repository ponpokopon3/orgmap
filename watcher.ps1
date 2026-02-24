<#
 watcher.ps1
 Waits for the parent PID to exit, then removes the `subst` mapping for the provided drive.
 Usage: powershell -File watcher.ps1 -ParentPid <pid> -Drive Q:
#>

param(
  [Parameter(Mandatory=$true)][int]$ParentPid,
  [Parameter(Mandatory=$false)][string]$Drive = 'Q:'
)

function Remove-Subst {
  param([string]$drive)
  try {
    & cmd /c "subst $drive /d" | Out-Null
  } catch {
    # ignore errors
  }
}

try {
  while ($true) {
    try {
      # if parent process no longer exists, Get-Process will throw
      Get-Process -Id $ParentPid -ErrorAction Stop | Out-Null
      Start-Sleep -Seconds 1
    } catch {
      break
    }
  }

  # brief pause to allow handles to be released
  Start-Sleep -Seconds 1
  Remove-Subst -drive $Drive
} catch {
  # keep watcher silent on errors
}
