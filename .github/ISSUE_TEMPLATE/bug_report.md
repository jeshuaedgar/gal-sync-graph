---
name: Bug report
about: Something does not work as documented
title: ""
labels: bug
assignees: JeshuaEdgar
---

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior, and which target you used (`-AllUsers`, `-TargetGroup` or `-TargetMailbox`).

**Expected behavior**
A clear and concise description of what you expected to happen.

**Diagnostics**
Paste the output of `Get-GALDiagnostic`. It leaves out secrets, tokens, tenant and application IDs and email addresses, but read it before you post.

In Azure Automation, start the `GAL-Sync` runbook with `Diagnostic` set to true (and `DiagnosticMailbox` for a mailbox that fails) and copy the job output. Otherwise:

```powershell
Get-GALDiagnostic -Mailbox <a mailbox that fails> -Result $results | Set-Clipboard
```

```
(paste here)
```

**Logs**
If applicable, add logs to help explain your problem. Run with `-Verbose` (or set `verboseLogging = true` in Azure Automation) for the most detailed output. Remove names and email addresses before posting.

**Environment (please complete the following information):**

- GAL-Sync version [e.g. 1.0.0-beta1]
- Where it runs [e.g. Azure Automation, Task Scheduler, interactive]
- Authentication [e.g. managed identity, certificate, client secret]
- PowerShell version [output of `$PSVersionTable.PSVersion`]

**Additional context**
Add any other context about the problem here.
