# LinkedIn Post — MakeMeAdminCLI v1.1.0 🦈🔥

**Ever typed `net localgroup Administrators` and wished it could just... handle itself?** 😩

I got tired of the admin rights dance. You know the one:

1️⃣ Open elevated PowerShell
2️⃣ Add yourself to Administrators
3️⃣ Forget to remove yourself
4️⃣ Security team sends you *that* email 📧😬

So I built something about it. 💪

**MakeMeAdminCLI** — a PowerShell module that gives you temporary local admin rights with automatic expiration. No GUI. No tickets. No forgetting to clean up. ✅

```
Add-TempAdmin                                # 🚀 15 min of admin rights
Invoke-AsAdmin mmc.exe diskmgmt.msc         # 💻 Disk Management, elevated, zero UAC
Remove-TempAdmin                             # 🛑 Done early? Drop rights instantly
```

---

🔧 **What's under the hood:**

A SYSTEM-level service listens on a named pipe. When you request elevation, it:

🔐 Validates your identity through Windows pipe impersonation (not from JSON — the OS itself confirms who you are)
👥 Adds you to the local Administrators group
⏰ Creates an independent scheduled removal task with 3 retry attempts
📝 Logs everything to Windows Event Log

The removal task survives service crashes, reboots, and power failures. Your admin rights **WILL** expire. That's the point. 🎯

---

🏆 **The v1.1.0 feature I'm most proud of:**

`Invoke-AsAdmin` launches elevated programs through the SYSTEM service using Microsoft's own ServiceUI.exe — completely bypassing UAC prompts. Need elevated PowerShell? `Invoke-AsAdmin powershell`. Disk Management? `Invoke-AsAdmin mmc.exe diskmgmt.msc`. It just works. ✨

---

🛡️ **For IT teams and security-conscious orgs:**

- 🔒 AllowedUsers / DeniedUsers ACLs (deny takes precedence, as it should)
- ⏱️ Configurable min/max duration limits
- 📊 Full audit trail via Event Log (Event IDs 1005, 1006, 1050, 1060)
- 🌍 Language-independent — uses Windows SIDs, not localized group names
- 💻 Works on Windows 10/11 and Server 2016+

---

**Pure PowerShell . MIT licensed.** 🎉

```
Install-Module MakeMeAdminCLI
```

🔗 GitHub: https://github.com/SharkByte561/MakeMeAdminCLI
📦 PowerShell Gallery: https://www.powershellgallery.com/packages/MakeMeAdminCLI

Inspired by Sinclair Community College's MakeMeAdmin — an excellent GUI tool that's been serving IT teams for years. MakeMeAdminCLI takes that concept and rebuilds it for the terminal. 🙏

If you manage endpoints, support devs who need occasional admin access, or just want to stop leaving yourself in the Administrators group overnight 😅 — give it a try and let me know what you think! 💬👇

#PowerShell #SysAdmin #Windows #InfoSec #OpenSource #CyberSecurity #DevOps #Automation #ZeroTrust #PrivilegeManagement
