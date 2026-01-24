# Contributing to MakeMeAdminCLI

Thank you for your interest in contributing to MakeMeAdminCLI!

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a feature branch: `git checkout -b feature/your-feature-name`

## Development Setup

```powershell
# Clone the repo
git clone https://github.com/YOUR_USERNAME/MakeMeAdminCLI.git
cd MakeMeAdminCLI

# Install for development (from admin PowerShell)
.\Install-MakeMeAdminCLI.ps1

# Run tests
.\Test-MakeMeAdminCLI.ps1 -Detailed
```

## Code Style

- Use approved PowerShell verbs (`Get-`, `Set-`, `Add-`, `Remove-`, etc.)
- Include comment-based help for all public functions
- Follow [PowerShell Best Practices](https://poshcode.gitbook.io/powershell-practice-and-style/)
- Use `Write-Verbose` for diagnostic output, not `Write-Host`

## Testing

Before submitting a PR:

1. Run `.\Test-MakeMeAdminCLI.ps1` and ensure all tests pass
2. Test on both PowerShell 5.1 and PowerShell 7+ if possible
3. Test as both admin and non-admin user

## Pull Request Process

1. Update CHANGELOG.md with your changes
2. Update README.md if you've added new features
3. Ensure all tests pass
4. Create a PR with a clear description of changes

## Reporting Issues

When reporting bugs, please include:

- PowerShell version (`$PSVersionTable`)
- Windows version
- Steps to reproduce
- Expected vs. actual behavior
- Relevant Event Log entries (`Get-EventLog -LogName Application -Source MakeMeAdminCLI -Newest 10`)

## Security Issues

For security vulnerabilities, please do NOT open a public issue. Instead, contact the maintainer directly.
