# Automatic USB startup

The GUI's **Automatic startup** tab can reapply the existing unlock before Windows on a cold boot. Leave the validated USB connected and use the tested display arrangement. GPU state remains volatile. This option does not establish persistence through sleep, hibernation, GPU resets or every restart.


## Register and test

1. Complete capture, validation/build and USB staging using this project folder. The startup checks require the staged files to match the current local build and its host-test evidence.
2. Close the GUI. Right-click **Launch Prometheus Unlock.cmd** and choose **Run as administrator**.
3. Select the correct USB under **Prepare and build**.
4. Open **Automatic startup** and click **Register test boot entry**. This adds `Prometheus Unlock USB - EXPERIMENTAL` at the end of the firmware boot menu. Existing default priority remains first.
5. Save work, fully shut down and select that named entry from the one-time firmware boot menu. Use the same monitor layout as the captured profile.
6. Once Windows returns, reopen the GUI as administrator. Select the USB and review its latest unlock report.
7. Click **Enable automatic USB startup** and confirm that the registered entry returned successfully to Windows. A fresh successful transaction log and a Windows boot after registration are required.

Enabling puts the registered USB entry first and Windows Boot Manager second. Other firmware entries remain in the order. It disables Windows Fast Startup to make normal shutdowns suitable for the cold-boot workflow. The prior Fast Startup value is saved for recovery. Confirm the next automatic cold boot physically and check its report.

The GUI does not reboot the machine itself. Firmware implementation differences can prevent a registered entry from working, even when the files and host tests are valid. Registering and testing the actual entry is part of installation.

## Restore normal boot

Click **Restore Windows first** to move Windows Boot Manager to the front and restore the saved Fast Startup value. This recovery action works with the USB removed and with missing build files. The test entry remains available later in the menu. If state is missing or unreadable, Windows-first order can still be restored, while the previous Fast Startup value may be unavailable.

If a test stays at a black screen, fully power off, remove the USB, and choose Windows Boot Manager from the firmware boot menu. After Windows starts, use the recovery button. Keep the captured monitor layout until any new layout has passed its own validation.

## Files and changes

Startup registration state and BCD backups are kept under `%ProgramData%\PrometheusUnlock`. Backups include the firmware entries and BCD export from before each mutation. Retain that folder for recovery. These machine-specific files are outside the distributable source package.

Boot changes require administrator access. The current BCDEdit parser requires English output and refuses an unrecognized boot-order format. Secure Boot must be off and the Windows system drive fully decrypted, as required by the experimental port. Pending one-time firmware boot requests cause the automation to stop.

The GUI prevents formatting, capture staging or unlock staging on a USB currently marked automatic. Restore Windows first before changing it. A changed build cannot be enabled under an old registration identity. For upgrades, click **Restore Windows first**, then **Remove test boot entry…** before changing the build. Removal checks that the entry belongs to this tool, restores normal boot and archives its state. Stage the new build, register a new test entry and repeat the supervised boot test before enabling automatic startup.

## Verification performed

`gui/test-startup.ps1` exercises simulated registration, promotion, recovery with the USB absent, idempotent enable, changed-build rejection, missing-boot-proof rejection, pending-boot rejection, registration failure, promotion rollback, malformed boot-order rejection, and the production success-log/timestamp checks. It uses temporary files and simulated firmware/registry functions.

These software tests do not establish hardware reliability. Automatic registration and boot priority still require a supervised physical boot test on each machine. No guarantee of 100% reliability is made.
