# Windows GUI

A Tkinter desktop front end for the existing local-profile workflow. The GUI provides hardware and USB inventory, confirmed FAT32 formatting, compiler/firmware preparation, capture USB creation, compatibility checks, profile generation, host tests, unlock staging and boot-log viewing.

## Start

Install Python 3.14 x64 with Tcl/Tk, 7-Zip, and Visual Studio Build Tools with the **Desktop development with C++** workload and Windows SDK. Extract the whole source package to a writable local folder, then double-click **Launch Prometheus Unlock.cmd** in the package root. Formatting requires administrator access. Existing FAT32 media can skip formatting.

The detailed instructions are in the GUI's **Step-by-step guide** tab and [HOW-TO.txt](HOW-TO.txt).

## Compatibility

The automatic candidate list is read from `research/profile/proven.json`. It currently includes exact PCI IDs for RTX 3060 12GB, RTX 3060 Ti, RTX 3070, RTX 3080 12GB, RTX 3090 and RTX 3090 Ti. Firmware and topology checks determine whether an individual machine is eligible. The port's fixed RTX 3070 Ti configuration is documented in the compatibility tab, with automatic local generation unavailable for that model.

The GUI reuses the existing source-bound profile, test and staging checks. It builds an observation-only capture program explicitly. Destructive formatting requires a typed confirmation and rechecks the selected USB's disk identity. Unlock staging requires a separate confirmation. The interface permits one operation at a time and one GUI instance per source tree.

## Build inputs and provenance

`vendor/generate_v67.py`, `vendor/extract_boot_assets.py` and `vendor/artifacts-610.43.03.json` are copied from Zagitta/gpu-unlock commit `0ebdb1c6308b6a2072be5bf04513472942541956`. `vendor/extract_gsp.py` is copied from the supplied Linux project. SPDX license notices are preserved. The parent port includes the applicable license texts.

Setup uses LLVM 20.1.8 with the release asset's pinned SHA-256, the pinned NVIDIA source archive, and NVIDIA's official 610.43.03 Linux installer as a data source. All generated firmware files must match the Windows port's expected sizes and hashes. The installer is extracted without execution. This replaces the old package-mirror dependency whose URL returned 404 during development.

Official dependency downloads are available from [Python](https://www.python.org/downloads/windows/), [7-Zip](https://www.7-zip.org/) and [Visual Studio](https://visualstudio.microsoft.com/downloads/).

## Distribution

Run `python gui/package.py` to create `dist/Prometheus-Unlock-source.zip`. It includes tracked upstream source and the GUI, and excludes local captures, profiles, firmware, binaries and identifiers. A recipient builds for their own machine. This is a source distribution requiring the dependencies above.

## Validation limits

Automated tests cover GUI routing, catalog admission boundaries, verified downloads, installer orchestration and simulated startup/recovery. Firmware entry registration, unattended cold boot, fresh-machine dependency installation and other GPU models require physical validation. See [release validation](../RELEASE-VALIDATION.md).
