# Install and use Prometheus Unlock

## 1. Prepare Windows

Use an x64 Windows PC with an eligible NVIDIA GPU, internet access and several GB of free storage. Visual Studio may require additional space beyond that for the project and firmware. Use a spare USB with a FAT32 volume of 1–32 GB. USB formatting erases all files on the selected volume.

Extract the full project folder to a writable local location, for example `C:\Tools\Prometheus Unlock`. Keep all folders together. The GUI and scripts use their own location to find the source files.

## 2. Run the guided installer

Double-click **Install Prometheus Unlock.cmd**.

The script checks for Python 3.14 with Tcl/Tk, 7-Zip and the MSVC C++ toolchain. If any are missing, it lists them and asks whether to install them using Windows Package Manager. Type `Y` to proceed and approve any Windows administrator prompts from the official installers. The Visual Studio installation requests the C++ build workload and recommended components, including the SDK.

Setup then downloads LLVM 20.1.8, verifies its package hash, extracts it locally, downloads the NVIDIA inputs and verifies the five resulting firmware files against the port's pinned hashes. The NVIDIA installer is opened as an archive for firmware extraction. The installed Windows display driver remains the runtime driver.

Successful setup opens the GUI. On later visits, double-click **Launch Prometheus Unlock.cmd**. Setup can be rerun after an interrupted download or a missing prerequisite is repaired. An installer-requested restart should be completed before retrying.

The launchers use a process-scoped PowerShell execution-policy option. Managed computers may enforce an organizational policy that requires an administrator-approved installation method.

### Manual dependency installation

If `winget` is unavailable, install or update Microsoft's **App Installer** through Microsoft Store, or install the dependencies manually. Then rerun setup.

- Install Python 3.14 x64 with Tcl/Tk. The Python launcher or the standard Python installation location allows the scripts to find it. An existing compatible `uv` Python installation is also detected. [Python downloads](https://www.python.org/downloads/windows/)
- Install 7-Zip x64 in its standard location or make `7z.exe` available on PATH. [7-Zip downloads](https://www.7-zip.org/)
- Install Visual Studio Build Tools and select **Desktop development with C++**, MSVC x64/x86 tools, and a Windows SDK. For an existing Visual Studio installation, choose **Modify** in Visual Studio Installer and add those components. [Microsoft C++ installation instructions](https://learn.microsoft.com/en-us/cpp/overview/acquire-msvc?view=msvc-170)

### Script options

From PowerShell in the project folder, the following command checks prerequisites without installing packages or downloading build inputs.

```powershell
.\Install.ps1 -CheckOnly
```

For unattended dependency consent with visible installer prompts as required, run the following command. It accepts the package agreements through Windows Package Manager.

```powershell
.\Install.ps1 -InstallDependencies -NoLaunch
```

To check/install prerequisites while postponing the large compiler and firmware downloads, use `-SkipDownloads`. Later, click **Download build inputs** in the GUI or rerun setup without that option.

## 3. Check firmware boot settings

Open **System Information** and inspect **Secure Boot State**. This unsigned experimental workflow requires it to be off. Open **Manage BitLocker** and confirm the Windows system drive is fully decrypted and shows BitLocker off. Keep recovery keys private. The GUI reports unknown when Windows denies access to these checks.

Any necessary BIOS or encryption changes are manual. Consult the PC/motherboard documentation for the setting and retain recovery information before changing it. A suspended but still encrypted drive differs from a fully decrypted drive.

## 4. Select and prepare the USB

1. Connect the spare USB and click **Refresh hardware**.
2. Check the selected drive letter, model and size. External backup disks may also appear in this list.
3. If the selected volume already uses FAT32, skip formatting. Otherwise click **Format USB**, read the erase prompt and type the exact confirmation.
4. If formatting reports access denied, close the GUI, right-click **Launch Prometheus Unlock.cmd**, choose **Run as administrator**, and select the USB again.
5. Click **Prepare capture USB**. The tool archives existing active captures and the prior boot loader, then builds and verifies the observation-only USB loader.

Formatting volumes over 32 GB is outside this script's formatting path. Use a smaller USB or prepare an appropriately sized FAT32 volume manually. Formatting affects the selected volume, so review other partitions separately if your USB has several.

## 5. Collect two cold-boot captures

1. Save work and run `shutdown /s /t 0` in a terminal.
2. Leave one monitor connected to the target GPU. Physically disconnect the other display cables for the initial setup.
3. Power on and open the motherboard's one-time boot menu. ASUS desktop systems commonly use **F8**. Choose the USB's **UEFI** entry.
4. Let the tool collect data and start Windows.
5. Fully shut down and perform the same USB boot a second time. Keep the same monitor and GPU port connected.
6. Open the GUI, refresh hardware, select the USB and click **Check two captures**.

A candidate result allows the next validation stage. If the checker rejects the captures, read its explanation. For a changed monitor arrangement, click **Prepare capture USB** to archive the previous pair, then collect two new captures. Preserve the complete capture set with its corresponding firmware image files.

## 6. Generate, test and build

Click **Validate and build**. This uses the current machine's Windows EFI partition, generates a local profile from the captures, parses the GPU firmware, runs the required host checks, and builds the USB wrapper and unlock program. Allow several minutes.

Expected rejection tests can print `FAIL` as part of a passing negative test. Check the final result of the entire command. Any failed job or stale source/input check stops the build. Source changes after testing require fresh validation.

## 7. Stage the actual unlock

After a successful build, click **Write unlock to USB** and read the confirmation. This replaces the capture loader with the program that will attempt GPU register writes at the next USB boot. The previous loader is kept in the USB backup folder.

Use the same single-monitor arrangement as the captures. Fully shut down and select the USB from the one-time firmware boot menu. Let it run without pressing keys. The initial five-second **Esc** window skips the attempt and starts Windows. A later three-second **Esc** window occurs after display release and stops the process.

The display may go black while firmware ownership is released. Windows should start after the attempt. This is the first hardware validation of the new build, even when all host tests passed.

## 8. Inspect the result

Once Windows has returned, click **Read latest boot result**. A report ending with `FINAL status=0` and `clean=1` records successful transaction completion and cleanup. Confirm that Windows returned in that same attempt. Old logs do not establish the GPU's current state.

Compare the same CUDA workload, model, precision and settings before and after. Matrix throughput improvements do not predict identical application-level gains.

## Recovery and common issues

| Situation | Action |
| --- | --- |
| Black screen that does not recover | Fully power off, remove the USB, and start Windows normally. Preserve the logs before another attempt. |
| USB absent from boot menu | Check FAT32, `EFI\BOOT\BOOTX64.EFI`, the UEFI boot mode and the USB connection. Consult the motherboard manual. |
| Missing C++ compiler or SDK | Modify Visual Studio Build Tools to add Desktop development with C++ and a Windows SDK, then rerun validation. |
| Hash mismatch | Preserve the error and identify the exact input. Obtain the correct original artifact and rerun setup. |
| Firmware/topology outside supported scope | Review the compatibility guide. Additional capture boots with the same rejected configuration do not add support. |
| Source/profile changed after tests | Run Validate and build again before staging. |
| USB removed or drive letter changed | Reconnect it, refresh hardware and select it again. |
| PowerShell or installer blocked by management policy | Use the organization's approved software installation process. |

Use manual USB boot selection while validating. Restarts, sleep, hibernation, driver resets and full power-off can change unlock state. Extra monitors after Windows startup are a separate test; boot-time use must satisfy the captured profile.

## Share with another user

For automatic cold-boot use after successful validation, follow [AUTOMATIC-STARTUP.md](AUTOMATIC-STARTUP.md). The USB must stay connected and the tested monitor arrangement must be used.

Use `dist/Prometheus-Unlock-source.zip`, created by `python gui/package.py`. The source manifest excludes your captures, downloaded firmware, generated profiles, partition identifiers and compiled EFI files. Each recipient runs setup, collects their own two captures and builds for their own machine.

Keep the upstream license files and attribution with any redistribution. Consult `gui/README.md` for extraction-tool provenance and the retained upstream documentation for hardware limitations.
