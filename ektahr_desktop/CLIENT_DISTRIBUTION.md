# EktaHR Desktop Agent – Client distribution

The agent is built as a self-contained desktop app with **all features** (attendance, screenshots, Tesseract OCR, SQLite, etc.). No features are removed.

## What to share with clients

Share **one file**:

| Artifact | Use case |
|----------|----------|
| **`output\EktaHR-Agent-Setup.exe`** | Client installer. Use this for all installs and updates so Windows replaces the existing app. |
| **`output\EktaHR-Agent-Portable.exe`** | Portable/internal build only. Do not send this to already-installed clients, or Windows may show it as a separate app. |

The portable exe is produced by both build scripts, but client updates should use the installer.

## How to build

From repo root:

```powershell
cd ektahr_desktop
.\build-agent.ps1
```

Output: **`ektahr_desktop\output\EktaHR-Agent-Portable.exe`** — portable/internal build only.

With installer (requires Inno Setup 6):

```powershell
.\build-and-package.ps1
```

Output: **`output\EktaHR-Agent-Portable.exe`** (portable/internal build) and **`output\EktaHR-Agent-Setup.exe`** (installer for clients).

## Single-file behavior (no feature loss)

- **One exe:** All managed code, native SQLite, and Tesseract tessdata are bundled; they extract at runtime to a temp folder. Clients only need the one .exe.
- **InvariantGlobalization:** Culture DLLs omitted for smaller size.
- **Self-contained:** Clients do not need to install .NET.

## Client usage

- **Installer:** Send `EktaHR-Agent-Setup.exe` for all client installs and updates.
- **Portable exe:** Use `EktaHR-Agent-Portable.exe` only for internal/dev testing. Do not use it to update an installed client.
