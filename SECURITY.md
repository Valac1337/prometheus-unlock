# Security and recovery

Prometheus Unlock runs experimental code before Windows and depends on exact firmware behavior. Host tests do not establish safety on every motherboard or GPU. Keep the documented Windows Boot Manager recovery path available.

For a GUI or installer bug, report the release version, Windows version, action taken, and a sanitized error summary. For an issue that may expose credentials or enable unauthorized disk/boot changes, contact the repository maintainer through an available private reporting channel before posting sensitive details. This source package does not define a maintainer email address.

Never post BitLocker recovery keys, raw capture sets, firmware images, disk serial numbers, account names or personal filesystem paths. Remove sensitive values from any screenshot or log excerpt before sharing.

If a test boot hangs, fully power off, remove the USB, and select Windows Boot Manager. The GUI's Windows-first recovery works independently of USB presence. See AUTOMATIC-STARTUP.md for limitations and recovery state.
