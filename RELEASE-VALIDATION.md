# Release validation

The release includes automated regression tests for the GUI, GPU catalog boundaries, verified downloads, public-source privacy checks, upstream tools and profile validation. PowerShell tests simulate installer orchestration and firmware boot registration, promotion, rollback, removal and recovery. Run the commands in CONTRIBUTING.md; GitHub Actions repeats them on Windows after publication.

## Local checks completed (2026-11-12)

- 162 Python tests passed: 13 GUI/download/privacy tests, 18 public-tool tests and 131 profile tests.
- 34 simulated startup assertions passed, including removal and recovery; installer simulation passed.
- GUI Python compilation and PowerShell parsing passed; installed prerequisite detection passed.
- Build-input setup extracted LLVM and verified all five firmware assets from cached upstream downloads.
- The read-only capture EFI compiled and passed PE structure and source-manifest verification. It was not staged or booted during this release check.
- The public allowlist and source ZIP passed the privacy and archive checks. GitHub-hosted CI has not yet run.

## Hardware limits

Automated tests do not prove that every GPU, motherboard, display arrangement or firmware implementation works. Seven exact PCI IDs are candidates for automatic local profile generation; the wider catalog is informational. Each machine must pass its own capture and source-bound build checks. Automatic USB startup requires a supervised physical test of the registered entry before promotion.

Fresh-machine dependency installation, automatic firmware boot selection and additional GPU models have not been physically validated for this release. No 100% reliability or permanent hardware modification is claimed.

## Privacy and packaging

SOURCE-FILES.json is the public allowlist. The release audit rejects private generated files, recognized credentials and personal Windows home paths. Original public upstream attribution, compatibility evidence and synthetic privacy-test examples are retained. Automated scanning is a safeguard, not proof that arbitrary future edits contain no sensitive information.

SOURCE-MANIFEST.json records SHA-256 hashes of the public files other than itself. Packages contain only audited source. Machine captures, generated profiles, firmware downloads, EFI binaries and startup state are excluded. Never upload the entire working folder or raw diagnostic captures.
