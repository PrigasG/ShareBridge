# ShareBridge

**ShareBridge** is a local deployment framework for packaging and distributing Shiny apps in restricted Windows environments.

It is designed for teams that:
- do not have admin rights
- want to avoid traditional installers like Inno Setup or MSI packaging
- need a simple SharePoint or OneDrive based distribution workflow
- want portable Shiny app delivery with bundled packages and optional bundled R

ShareBridge lets a publisher package a Shiny app into a single deployable folder, place it in SharePoint, and have end users sync and run it locally. No Shiny Server, no admin rights, and no R installation required on user machines when portable R is bundled.

---

## What ShareBridge does

ShareBridge provides:

- a local Publisher UI for packaging Shiny apps
- automatic package detection and bundling
- optional offline package repository creation
- optional portable R bundling
- optional Pandoc support for R Markdown rendering
- optional writable directory provisioning
- hidden background publishing with live logs
- a clean end-user launcher experience
- local app launch through a friendly loopback URL such as:

```text
http://sharebridge-my_app.localhost:3670
```

---

## Core workflow

### Publisher workflow
1. Open the **ShareBridge Publisher** (double-click `PublishApp.hta`)
2. Select the source Shiny app folder
3. Enter the app name
4. Review detected packages and add extras if needed
5. Choose the output folder
6. Optionally enable:
   - zip output
   - offline repo
   - Pandoc support stub
   - writable app directories
7. Click **Build deployment**
8. Copy the completed output folder to SharePoint or another synced location

### End user workflow
1. Sync the published folder locally through OneDrive or SharePoint sync
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
|   `-- publisher/             # Publisher and strip_r logs
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
| `publish.bat` | Batch fallback launcher |
| `build/publisher_ui/app.R` | Shiny-based packaging interface |
| `build/publish_app.R` | Builds the final deployable app folder |
| `build/build_packages.R` | Bundles app package dependencies |
| `strip_r.R` | Creates the portable R master copy |
| `build/run_hidden.vbs` | Launches background processes without a console window |

### Deployment side

| File | Purpose |
|------|---------|
| `LaunchApp.hta` | Hidden launcher for deployed apps |
| `run.bat` | Starts the local runtime |
| `run.R` | Loads bundled dependencies and launches the Shiny app |
| `app_meta.cfg` | App metadata such as name, ID, preferred port |
| `req.txt` | Required package list |
| `VERSION` | Build metadata and R version details |

---

## Publisher app features

The Publisher UI supports:

- selecting a Shiny app source folder (with native Windows folder picker)
- auto-detecting packages used in the app code
- adding optional extra packages manually
- choosing an output directory
- optionally creating a zip file
- optionally building an offline package repo
- optionally enabling Pandoc support stub
- optionally selecting writable app directories to provision
- showing a live build log during the build
- building in the background with no console window (via VBScript + processx)
- saving publisher logs under `logs/publisher/`
- viewing and deleting saved publisher logs from the UI
- creating portable R directly from the Publisher UI (Strip R tab)
- clearing the form for a new build without refreshing

---

## Supported app layouts

ShareBridge supports either:

**Single-file app:**
- `app.R`

**Split app:**
- `ui.R` + `server.R`

It also supports common supporting folders such as:
`www/`, `R/`, `modules/`, `data/`, `config/`, and helper `.R` files.

---

## Packaging behavior

During publishing, ShareBridge:

1. Validates the source app structure (checks for `app.R` or `ui.R` + `server.R`)
2. Copies the source app into the output folder under `app/`
3. Detects package dependencies via `renv::dependencies()` with regex fallback
4. Writes `req.txt` with auto-detected packages (always includes `shiny`)
5. Merges optional extra packages from the UI or `req_extra.txt`
6. Writes `app_meta.cfg` with app name, ID, preferred port, and host metadata
7. Copies portable R from the framework into the deployment as `R/` when available
8. Writes `VERSION` with R version, build timestamp, and package count
9. Calls `build_packages.R` to build the bundled package library
10. Optionally creates selected writable directories in the deployment
11. Optionally prepares a Pandoc support stub folder
12. Optionally builds a local offline repo under `repo/`
13. Optionally creates a zip archive of the final deployment

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
|-- pandoc/                 # optional Pandoc stub
`-- repo/                   # optional offline repo
```

---

## Portable R workflow

ShareBridge separates the portable R source from the portable R runtime.

### Folders
- `R-portable-master/` — master source copy used for publishing
- `R-portable/` — runtime copy used for local launching and testing

This split avoids Windows file-locking problems during publishing.

### Creating portable R

1. Install a full version of R on the publisher machine
2. Run strip_r.R from the Publisher UI (Strip R tab) or command line:
   ```
   Rscript strip_r.R --r_source "C:\Path\To\R"
   ```
3. ShareBridge creates `R-portable-master/` and optionally refreshes `R-portable/`

### Why this design is used
- Publishing should copy from a cold source tree
- Runtime and testing may lock DLLs in a live tree
- Separating master and runtime makes builds more reliable

### What gets stripped

Documentation, test suites, Tcl/Tk runtime, C headers, translations, and help/vignette files from all base packages. All runtime code, DLLs, NAMESPACE, and DESCRIPTION files are preserved.

---

## Dependency detection

ShareBridge detects packages automatically from app source code.

**Detected patterns:**
- `library(pkg)` and `require(pkg)`
- `pkg::function()` and `pkg:::function()`

**Files scanned:** `.R`, `.Rmd`, `.qmd`

**Primary scanner:** `renv::dependencies()` (if renv is installed)
**Fallback scanner:** built-in regex parser

**What static scanning can miss:**
- Dynamic loading: `lapply(pkgs, library, character.only = TRUE)`
- String-constructed names: `library(paste0("data", ".table"))`
- Packages loaded in externally sourced scripts outside the app folder

For these cases, publishers can add extra packages manually in the Publisher UI or via a `req_extra.txt` file.

---

## Writable app directories

ShareBridge can optionally ensure selected app subdirectories exist in the deployment.

This is useful for apps that expect writable folders such as `data/`, `uploads/`, `cache/`, or `tmp/`.

Important:
- This only provisions directories in the deployment output
- It does not modify the Shiny app code
- The app itself must still reference and use those folders
- Directories that already exist in the source app are detected and offered for selection

---

## Pandoc support

ShareBridge supports an optional Pandoc preparation mode.

When the **Include Pandoc** option is enabled:
- ShareBridge creates a `pandoc/` folder in the deployment output
- ShareBridge writes a `README_Pandoc.txt` into that folder
- ShareBridge adds relevant R Markdown support packages to `req.txt`

By default, ShareBridge does not copy a Pandoc installation automatically. This keeps deployment size smaller. If your app needs PDF generation or R Markdown rendering, place a local Pandoc installation into `pandoc/` with `pandoc/pandoc.exe`. At runtime, ShareBridge will use that local Pandoc folder if present.

---

## Launch behavior

End users launch apps through `LaunchApp.hta`, which starts the local runtime without showing a console window.

Apps open in a browser using a friendly local loopback URL such as:

```text
http://sharebridge-my_app.localhost:3670
```

If the preferred port is already in use, ShareBridge falls back to a random local port.

---

## Port assignment

Each app gets a deterministic preferred port derived from its app ID, in the range 3400–4400. This ensures two different apps published through ShareBridge default to different ports without manual configuration.

If the preferred port is unavailable at launch time, `run.R` falls back to a random port via `httpuv::randomPort()`.

---

## Logging

### Publisher logs

Stored in `logs/publisher/`. Each build and strip_r operation creates a timestamped log file. Logs older than 30 days are cleaned automatically.

These logs help diagnose failed builds, dependency issues, portable R copy problems, and package bundling issues. They can be viewed and deleted from within the Publisher UI.

### Runtime logs

Deployed apps create logs during launch via `run.bat`. Logs are typically written to a temp location (`%TEMP%\{APP_ID}_logs\`), with fallback to the local `logs/` folder. Logs older than 7 days are cleaned automatically.

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
- Required R packages: `shiny`, `processx`, `jsonlite`

### End user machine
- Windows
- SharePoint or OneDrive sync available
- No admin rights required (if R and packages are bundled)
- No R installation required (if portable R is bundled)

---

## Recommended distribution model

1. Build the deployment locally using the Publisher UI
2. Copy the output folder to SharePoint or a synced network location
3. Have users sync the folder locally
4. Tell users to open `LaunchApp.hta`

This avoids admin installs, MSI packaging, per-user R setup, and direct package installation on user machines.

---

## Known limitations

- **OneDrive sync lag:** Users may launch before all files are synced. The app may fail with "package not found" until sync completes.
- **Path length limits:** Deeply nested synced folders can hit Windows' 260-character path limit. Keep app folder names short.
- **HTA restrictions:** Some environments block `.hta` files via Group Policy. Use `run.bat` as a fallback.
- **Writable data in synced folders:** Frequently written app data should not live inside the synced deployment folder. Use a shared network drive path via `DATA_DIR` in `app_meta.cfg`.
- **Pandoc not bundled automatically:** If your app needs Pandoc for PDF output, publishers must place Pandoc into the deployment `pandoc/` folder.

---

## Suggested improvements

### High priority
- Runtime detection and message when local Pandoc is missing but expected
- Runtime feature/config file written into each deployment for app-side behavior
- Publisher UI summary panel showing what will be bundled (portable R, offline repo, Pandoc stub, writable dirs)

### Medium priority
- Runtime version check between bundled R and expected R version at startup
- Deployment validation step after build
- Copy-to-SharePoint helper or post-build shortcut

### Nice to have
- Custom app icon and branding in the launch window
- Update notification against a central manifest
- Optional self-test mode that opens the deployment after build
- Publisher export/import profiles for repeatable builds
- Standalone `.exe` publisher wrapper (no R needed on publisher machine)

---

## License

ShareBridge is an internal deployment framework. If you bundle R and CRAN packages, retain the applicable third-party license notices and attribution requirements for redistributed components. R itself is licensed under GPL-2 | GPL-3.
