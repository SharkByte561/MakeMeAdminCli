# Changelog

All notable changes to MakeMeAdminCLI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-24

### Added
- Initial release
- `Add-TempAdmin` - Request temporary administrator rights with configurable duration
- `Remove-TempAdmin` - Revoke admin rights before automatic expiration
- `Get-TempAdminStatus` - Check current elevation status and remaining time
- `Set-TempAdminConfig` - View and modify configuration settings
- Named pipe IPC for secure client-server communication
- Windows Event Log integration for auditing (source: MakeMeAdminCLI)
- Automatic expiration via Task Scheduler with retry logic
- AllowedUsers/DeniedUsers access control lists
- Language-independent operation using Windows SIDs
- Convenient aliases: `mama`, `rmadmin`, `adminstatus`

### Security
- Server-side identity verification via named pipe impersonation
- Users can only elevate themselves (enforced server-side)
- Scheduled removal tasks persist even if service stops
- DeniedUsers takes precedence over AllowedUsers
