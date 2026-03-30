# ShareBridge

**ShareBridge** is a local deployment framework for packaging and distributing Shiny apps in restricted Windows environments.

It is designed for teams that:
- do not have admin rights
- want to avoid traditional installers like Inno Setup or MSI packaging
- need a simple SharePoint-based distribution workflow
- want portable Shiny app delivery with bundled packages and optional bundled R

ShareBridge lets a publisher package a Shiny app into a single deployable folder, place it in SharePoint, and have end users sync and run it locally — no Shiny Server, no admin rights, no R installation required on user machines.

---

## Core workflow

### Publisher workflow
1. Open the **ShareBridge Publisher** (double-click `PublishApp.hta`)
2. Select the source Shiny app folder
3. Enter the app name
4. Review auto-detected packages, add extras if needed
5. Choose the output folder
6. Click **Build deployment**
7. Copy the completed output folder to SharePoint

### End user workflow
1. Sync the published SharePoint folder locally
2. Double-click `LaunchApp.hta`
3. Optionally create a desktop shortcut to `LaunchApp.hta`

---

## Project structure

```text
ShareBridge/
|-- build/
|   |-- publisher_ui/
|   |   `-- app.R              # Publisher Shiny UI
|   |-- build_packages.R       # Package bundler
|   |-- publish_app.R          # Main build orchestrator
|   `-- run_hidden.vbs         # Hidden process launcher
|-- logs/
|   `-- publisher/             # Publisher build logs
|-- LaunchApp.hta               # User-facing app launcher
|-- PublishApp.hta               # Publisher launcher (HTA)
|-- publish.bat                  # Publisher launcher (batch fallback)
|-- run.bat                      # App runtime launcher
|-- run.R                        # App runtime entry point
|-- strip_r.R                    # Portable R builder
`-- ShareBridge.Rproj
```

---

## Main components

### Publisher side

| File | Purpose |
|------|---------|
| `PublishApp.hta` | Hidden launcher for the publisher app |
| `publish.bat` | Starts the publisher app in a local browser session |
| `build/publisher_ui/app.R` | Shiny-based graphical interface for packaging apps |
| `build/publish_app.R` | Assembles the final deployable app structure |
| `build/build_packages.R` | Builds the bundled package library and optional offline repo |
| `strip_r.R` | Creates a reduced portable R runtime from a full R installation |
| `build/run_hidden.vbs` | Runs background build processes without showing a console window |

### Deployment side

| File | Purpose |
|------|---------|
| `LaunchApp.hta` | Hidden launcher for deployed Shiny apps |
| `run.bat` | Runtime launcher that finds R and starts the app |
| `run.R` | Loads bundled dependencies and starts the Shiny app |
| `app_meta.cfg` | App name, ID, preferred port, host |
| `req.txt` | Auto-generated package dependency list |
| `VERSION` | Build metadata, R version, package count |

---

## Publisher app features

The Publisher UI supports:

- selecting a Shiny app source folder (with native Windows folder picker)
- auto-detecting packages used in the app code
- adding optional extra packages manually
- choosing an output directory
- optionally creating a zip file
- optionally building an offline package repo
- showing a live build log during the build
- building in the background with no console window (via VBScript + processx)
- saving publisher logs under `logs/publisher/`
- viewing and deleting saved publisher logs from the UI
- clearing the form for a new build without refreshing

---

## Input app requirements

ShareBridge supports either of these app layouts:

**Single-file app:**
- `app.R`

**Split app:**
- `ui.R` + `server.R`

It also supports additional folders and files commonly used in Shiny apps:
`www/`, `R/`, `modules/`, `data/`, `config/`, and helper `.R` files.

---

## Packaging behavior

During publishing, ShareBridge:

1. Validates the source app structure (checks for `app.R` or `ui.R` + `server.R`)
2. Copies the source app into the output folder under `app/`
3. Detects package dependencies via `renv::dependencies()` with regex fallback
4. Writes `req.txt` with auto-detected packages (always includes `shiny`)
5. Merges optional extra packages from `req_extra.txt` or the UI textarea
6. Writes `app_meta.cfg` with app name, ID, derived port, and host
7. Copies portable R from `R-portable/` into the output as `R/`
8. Writes `VERSION` with R version, build timestamp, and package count
9. Calls `build_packages.R` to install packages into `packages/`
10. Optionally builds a local offline repo under `repo/`
11. Optionally creates a zip archive of the output folder

### Typical output structure

```text
MyApp_deploy/
|-- LaunchApp.hta
|-- run.bat
|-- run.R
|-- req.txt
|-- app_meta.cfg
|-- VERSION
|-- README_User.txt
|-- README_Publisher.txt
|-- packages_manifest.tsv
|-- app/                    # user's Shiny app code
|-- packages/               # bundled CRAN packages
|-- logs/
|-- build/
|   `-- build_packages.R
|-- R/                      # optional portable R
`-- repo/                   # optional offline repo
```

---

## Dependency detection

ShareBridge detects packages automatically from the app source code.

**Detected patterns:**
- `library(pkg)` and `require(pkg)`
- `pkg::function()` and `pkg:::function()`
- Namespaced calls in any `.R`, `.Rmd`, or `.qmd` file

**Primary scanner:** `renv::dependencies()` (if renv is installed)
**Fallback scanner:** built-in regex parser

**What static scanning can miss:**
- Dynamic loading: `lapply(pkgs, library, character.only = TRUE)`
- String-constructed names: `library(paste0("data", ".table"))`
- Packages loaded in externally sourced scripts outside the app folder

For these cases, publishers can add extra packages manually in the Publisher UI or via a `req_extra.txt` file.

---

## Port assignment

Each app gets a deterministic preferred port derived from its app ID, in the range 3400–4400. This ensures two different apps published through ShareBridge will default to different ports without manual configuration.

If the preferred port is occupied at launch time, `run.R` falls back to a random port via `httpuv::randomPort()`.

---

## Portable R

ShareBridge can bundle a portable R runtime into each deployment.

### Creating portable R (one-time setup)

1. Download and install R into a user-writable location:
   ```
   R-4.x.x-win.exe /VERYSILENT /DIR="C:\R-build\R-4.x.x"
   ```
2. Run `strip_r.R` to create a stripped version:
   ```
   Rscript strip_r.R --r_source "C:\R-build\R-4.x.x"
   ```
3. The resulting `R-portable/` folder appears in the ShareBridge framework root (~100MB, stripped from ~300MB)

### What gets stripped

Documentation, test suites, Tcl/Tk runtime, C headers, translations, and help/vignette files from all base packages. All runtime code, DLLs, NAMESPACE, and DESCRIPTION files are preserved.

### Why bundle R

- Users do not have admin rights to install R
- Users do not already have R installed
- The runtime R version must match the bundled package library
- Each deployment is a sealed unit — updating one app never breaks another

---

## Logging

### Publisher logs

Stored in `logs/publisher/`. Each build creates a timestamped log file. Logs older than 30 days are cleaned automatically.

These logs help diagnose failed builds, dependency issues, packaging errors, and runtime preparation problems. They can be viewed and deleted from within the Publisher UI.

### Runtime logs

Deployed apps create logs during launch via `run.bat`. Logs are stored in `%TEMP%\{APP_ID}_logs\` with fallback to the local `logs/` folder. Logs older than 7 days are cleaned automatically.

---

## Launching

### Publisher
Use `PublishApp.hta` (recommended) or `publish.bat`. Do not launch `publish.bat` directly unless you specifically want to see console output.

### Deployed apps
End users should use `LaunchApp.hta`. This hides the console window and reads the app name from `app_meta.cfg` for the window title.

---

## Requirements

### Publisher machine
- Windows
- R available via one of:
  - `R-portable/` in the ShareBridge root
  - A system R installation
  - `Rscript.exe` on PATH
- Required R packages: `shiny`, `processx`

### End user machine
- Windows
- SharePoint/OneDrive sync available
- No admin rights required (if R and packages are bundled)
- No R installation required (if portable R is bundled)

---

## Recommended distribution model

1. Build the deployment locally using the Publisher UI
2. Copy the output folder to a SharePoint document library
3. Have users sync that location via OneDrive
4. Tell users to open `LaunchApp.hta`

This avoids admin installs, MSI packaging, and local package installation by end users.

---

## Known limitations

- **OneDrive sync lag:** Users might launch the app before all files have synced. The app may fail with "package not found" until sync completes.
- **MAX_PATH:** Deeply nested OneDrive paths can exceed Windows' 260-character path limit. Keep app folder names short and avoid deep SharePoint nesting.
- **HTA blocking:** Some corporate environments block `.hta` files via Group Policy. Use `run.bat` as a fallback launcher.
- **Shared writable data:** If your app writes to files (parquet, SQLite, etc.), do not store them in the synced folder. Use a shared network drive path configured via `DATA_DIR` in `app_meta.cfg`.

---

## Future improvements

- `DATA_DIR` support in `app_meta.cfg` for shared network drive data paths
- R version check in `run.R` at startup (compare `RVersionMajorMinor` from `VERSION` against running R)
- Standalone `.exe` publisher wrapper (no R needed on publisher machine)
- shinyapps.io hosted publisher UI for remote access
- Update notification in `run.R` (check version against a central manifest)

---

## License

ShareBridge is an internal deployment framework. If you bundle R and CRAN packages, retain the applicable third-party license notices and attribution requirements for redistributed components. R itself is licensed under GPL-2 | GPL-3.
