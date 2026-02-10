# Examples: Invoke-AsAdmin usage
# Run Add-TempAdmin (mama) first to get an active elevation session.

# 1. Launch an elevated PowerShell window
Invoke-AsAdmin powershell

# 2. Launch a specific executable by full path
Invoke-AsAdmin "X:\Vault\Tools\VeraCrypt\VeraCrypt-x64.exe"

# 3. Launch Disk Management (.msc files need mmc.exe)
Invoke-AsAdmin mmc.exe diskmgmt.msc
