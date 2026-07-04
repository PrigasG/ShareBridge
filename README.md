---
editor_options:
  markdown:
    wrap: 72
---

# ShareBridge

**ShareBridge** is a local deployment framework for packaging and
distributing Shiny apps in restricted Windows environments.

It is designed for teams that: - do not have admin rights - want to
avoid traditional installers like Inno Setup or MSI packaging - need a
simple SharePoint or OneDrive based distribution workflow - want
portable Shiny app delivery with bundled packages and optional bundled R

ShareBridge lets a publisher package a Shiny app into a single
deployable folder, place it in SharePoint, and have end users sync and
run it locally. No Shiny Server, no admin rights, and no R installation
required on user machines when portable R is bundled.

------------------------------------------------------------------------

## What ShareBridge does

ShareBridge provides:

-   a local Publisher UI for packaging Shiny apps
-   a hosted Publisher/Inspector mode for Posit Connect Cloud and
    Hugging Face Spaces
-   automatic package detection and bundling
-   dependency review and preflight checks before publishing
-   a readiness score with **ShareBridge-ready**, **Needs review**, or
    **Blocked** status
-   build recipes and example apps for quick validation
-   optional offline package repository creation
-   optional portable R bundling
-   optional Pandoc support for R Markdown rendering
-   optional writable directory provisioning
-   hidden background publishing with live logs
-   downloadable diagnostics bundles for failed or questionable builds
-   downloadable readiness reports, user instructions, and IT handoff
    checklists
-   a clean end-user launcher experience
-   local app launch through a friendly loopback URL such as:

``` text
http://sharebridge-my_app.localhost:3670
```

------------------------------------------------------------------------

## Core workflow

### Publisher workflow

1.  Open the **ShareBridge Publisher** (double-click `PublishApp.hta`)
2.  Select the source Shiny app folder
3.  Enter the app name
4.  Review detected packages, dependency notes, and preflight checks
5.  Choose the output folder
6.  Optionally apply a build recipe or load an example app
7.  Optionally enable:
    -   zip output
    -   offline repo
    -   Pandoc support stub
    -   writable app directories
8.  Click **Build deployment**
9.  Copy the completed output folder or generated zip to SharePoint or another synced
    location

### End user workflow

1.  Sync the published folder locally through OneDrive or SharePoint
    sync
2.  Double-click `LaunchApp.hta`
3.  Optionally create a desktop shortcut to `LaunchApp.hta`

------------------------------------------------------------------------

## Project structure

``` text
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

------------------------------------------------------------------------

## Main components

### Publisher side

| File | Purpose |
|------------------------------------|------------------------------------|
| `PublishApp.hta` | Hidden launcher for the publisher app |
| `publish.bat` | Batch fallback launcher |
| `build/publisher_ui/app.R` | Shiny-based packaging interface |
| `build/publish_app.R` | Builds the final deployable app folder |
| `build/build_packages.R` | Bundles app package dependencies |
| `strip_r.R` | Creates the portable R master copy |
| `build/run_hidden.vbs` | Launches background processes without a console window |

### Deployment side

| File            | Purpose                                               |
|-----------------|-------------------------------------------------------|
| `LaunchApp.hta` | Hidden launcher for deployed apps                     |
| `run.bat`       | Starts the local runtime                              |
| `run.R`         | Loads bundled dependencies and launches the Shiny app |
| `app_meta.cfg`  | App metadata such as name, ID, preferred port         |
| `req.txt`       | Required package list                                 |
| `VERSION`       | Build metadata and R version details                  |

------------------------------------------------------------------------

## Publisher app features

The Publisher UI supports:

-   selecting a Shiny app source folder (with native Windows folder
    picker)
-   uploading a local app folder from hosted sessions such as Posit
    Connect Cloud or Hugging Face Spaces
-   auto-detecting packages used in the app code
-   reviewing dependency hints for report, data, and interactive UI
    packages
-   running preflight checks for structure, output, packages, Portable R,
    Pandoc, and local-only path risks
-   flagging common runtime dependency risks such as Java, geospatial
    libraries, browser tooling, ODBC, and credential handling packages
-   scanning app code for portability risks such as hard-coded paths,
    `setwd()`, interactive file pickers, references outside the app
    folder, and possible hard-coded secrets
-   showing a top-level readiness score and compatibility status
-   adding optional extra packages manually
-   choosing an output directory
-   applying build recipes for SharePoint/offline, small app, report app,
    hosted validation, and inspection workflows
-   loading built-in simple, data, and report example apps
-   optionally creating a zip file
-   optionally building an offline package repo
-   optionally enabling Pandoc support stub
-   optionally selecting writable app directories to provision
-   showing a live build log during the build
-   building in the background with no console window (via VBScript +
    processx)
-   saving publisher logs under `logs/publisher/`
-   viewing and deleting saved publisher logs from the UI
-   downloading a diagnostics zip with logs, preflight notes, package
    lists, and health-check results
-   downloading a Markdown readiness report for app owners or team review
-   downloading a user instruction file and IT handoff checklist
-   creating portable R directly from the Publisher UI (Strip R tab)
-   clearing the form for a new build without refreshing

------------------------------------------------------------------------

## Hosted Publisher/Inspector mode

When the Publisher UI runs on Posit Connect Cloud or Hugging Face
Spaces, it works as a hosted inspector and zip builder. Hosted sessions
can open the browser's local folder picker and upload the selected app
folder into the server session, but they cannot read arbitrary paths on
the user's computer.

Hosted mode therefore uses these rules:

-   **Source app:** use **Browse...** to upload the local app folder, or
    use the zip fallback.
-   **Output:** generated automatically inside the hosted runtime and
    returned as a downloadable zip.
-   **DATA_DIR:** saved as a runtime path for the eventual deployed app;
    data files that must be bundled should be inside the uploaded app
    folder or zip.
-   **Profiles:** save reusable options, but not uploaded files or
    generated hosted output paths.
-   **Portable R creation:** use the local Windows Publisher UI because
    hosted sessions cannot browse or package a local Windows R
    installation.

Hosted publishing is useful for validating app structure, reviewing
dependencies, checking for local path risks, and producing a downloadable
deployment zip. For local Windows distribution, end users still need the
complete ShareBridge deployment folder, including bundled Portable R
when they do not have R installed.

The hosted inspector is also useful before a team review. It produces a
readiness score, a Markdown readiness report, a diagnostics bundle, and
an IT checklist that summarize what should be fixed, approved, or
confirmed before distribution.

------------------------------------------------------------------------

## Supported app layouts

ShareBridge supports either:

**Single-file app:** - `app.R`

**Split app:** - `ui.R` + `server.R`

It also supports common supporting folders such as: `www/`, `R/`,
`modules/`, `data/`, `config/`, and helper `.R` files.

------------------------------------------------------------------------

## Packaging behavior

During publishing, ShareBridge:

1.  Validates the source app structure (checks for `app.R` or `ui.R` +
    `server.R`)
2.  Copies the source app into the output folder under `app/`
3.  Detects package dependencies via `renv::dependencies()` with regex
    fallback
4.  Writes `req.txt` with auto-detected packages (always includes
    `shiny`)
5.  Merges optional extra packages from the UI or `req_extra.txt`
6.  Writes `app_meta.cfg` with app name, ID, preferred port, and host
    metadata
7.  Copies portable R from the framework into the deployment as `R/`
    when available
8.  Writes `VERSION` with R version, build timestamp, and package count
9.  Calls `build_packages.R` to build the bundled package library
10. Optionally creates selected writable directories in the deployment
11. Optionally prepares a Pandoc support stub folder
12. Optionally builds a local offline repo under `repo/`
13. Optionally creates a zip archive of the final deployment

### Typical output structure

``` text
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

------------------------------------------------------------------------

## Portable R workflow

ShareBridge separates the portable R source from the portable R runtime.

### Folders

-   `R-portable-master/` — master source copy used for publishing
-   `R-portable/` — runtime copy used for local launching and testing

This split avoids Windows file-locking problems during publishing.

### Creating portable R

1.  Install a full version of R on the publisher machine

2.  Run strip_r.R from the Publisher UI (Strip R tab) or command line:

    ```
    Rscript strip_r.R --r_source "C:\Path\To\R"
    ```

3.  ShareBridge creates `R-portable-master/` and optionally refreshes
    `R-portable/`

Use the official [R for Windows download](https://cran.r-project.org/bin/windows/base/)
as the source installation. ShareBridge does not ship a prebuilt
Portable R binary by default. If you redistribute deployments with
bundled R, retain the applicable R license notices; R is licensed under
GPL-2 or GPL-3.

### Why this design is used

-   Publishing should copy from a cold source tree
-   Runtime and testing may lock DLLs in a live tree
-   Separating master and runtime makes builds more reliable

### What gets stripped

Documentation, test suites, Tcl/Tk runtime, C headers, translations, and
help/vignette files from all base packages. All runtime code, DLLs,
NAMESPACE, and DESCRIPTION files are preserved.

------------------------------------------------------------------------

## Dependency detection

ShareBridge detects packages automatically from app source code.

**Detected patterns:** - `library(pkg)` and `require(pkg)` -
`pkg::function()` and `pkg:::function()`

**Files scanned:** `.R`, `.Rmd`, `.qmd`

**Primary scanner:** `renv::dependencies()` (if renv is installed)
**Fallback scanner:** built-in regex parser

**What static scanning can miss:** - Dynamic loading:
`lapply(pkgs, library, character.only = TRUE)` - String-constructed
names: `library(paste0("data", ".table"))` - Packages loaded in
externally sourced scripts outside the app folder

For these cases, publishers can add extra packages manually in the
Publisher UI or via a `req_extra.txt` file.

------------------------------------------------------------------------

## Writable app directories

ShareBridge can optionally ensure selected app subdirectories exist in
the deployment.

This is useful for apps that expect writable folders such as `data/`,
`uploads/`, `cache/`, or `tmp/`.

Important: - This only provisions directories in the deployment output -
It does not modify the Shiny app code - The app itself must still
reference and use those folders - Directories that already exist in the
source app are detected and offered for selection

------------------------------------------------------------------------

## Pandoc support

ShareBridge supports an optional Pandoc preparation mode.

When the **Include Pandoc** option is enabled: - ShareBridge creates a
`pandoc/` folder in the deployment output - ShareBridge writes a
`README_Pandoc.txt` into that folder - ShareBridge adds relevant R
Markdown support packages to `req.txt`

By default, ShareBridge does not copy a Pandoc installation
automatically. This keeps deployment size smaller. If your app needs PDF
generation or R Markdown rendering, place a local Pandoc installation
into `pandoc/` with `pandoc/pandoc.exe`. At runtime, ShareBridge will
use that local Pandoc folder if present.

The Publisher UI links to the official Pandoc install page and GitHub
releases. Bundling Pandoc is usually a size and licensing decision, so
publishers should choose the approved version for their environment.

------------------------------------------------------------------------

## Launch behavior

End users launch apps through `LaunchApp.hta`, which starts the local
runtime without showing a console window.

Apps open in a browser using a friendly local loopback URL such as:

``` text
http://sharebridge-my_app.localhost:3670
```

If the preferred port is already in use, ShareBridge falls back to a
random local port.

------------------------------------------------------------------------

## Port assignment

Each app gets a deterministic preferred port derived from its app ID, in
the range 3400–4400. This ensures two different apps published through
ShareBridge default to different ports without manual configuration.

If the preferred port is unavailable at launch time, `run.R` falls back
to a random port via `httpuv::randomPort()`.

------------------------------------------------------------------------

## Logging

### Publisher logs

Stored in `logs/publisher/`. Each build and strip_r operation creates a
timestamped log file. Logs older than 30 days are cleaned automatically.

These logs help diagnose failed builds, dependency issues, portable R
copy problems, and package bundling issues. They can be viewed and
deleted from within the Publisher UI.

The Publisher UI can also download a diagnostics zip containing a
summary, current build log, selected saved log, package list, preflight
results, and health-check JSON when available.

### Runtime logs

Deployed apps create logs during launch via `run.bat`. Logs are
typically written to a temp location (`%TEMP%\{APP_ID}_logs\`), with
fallback to the local `logs/` folder. Logs older than 7 days are cleaned
automatically.

------------------------------------------------------------------------

## Launching

### Publisher

Use `PublishApp.hta` (recommended) or `publish.bat`. Do not launch
`publish.bat` directly unless you specifically want to see console
output.

### Deployed apps

End users should use `LaunchApp.hta`. This hides the console window and
reads the app name from `app_meta.cfg` for the window title.

------------------------------------------------------------------------

## Requirements

### Publisher machine

-   Windows
-   R available via one of:
    -   `R-portable/` in the ShareBridge root
    -   A system R installation
    -   `Rscript.exe` on PATH
-   Required R packages: `shiny`, `processx`, `jsonlite`

### End user machine

-   Windows
-   SharePoint or OneDrive sync available
-   No admin rights required (if R and packages are bundled)
-   No R installation required (if portable R is bundled)

------------------------------------------------------------------------

## Recommended distribution model

1.  Build the deployment locally using the Publisher UI
2.  Copy the output folder to SharePoint or a synced network location
3.  Have users sync the folder locally
4.  Tell users to open `LaunchApp.hta`

This avoids admin installs, MSI packaging, per-user R setup, and direct
package installation on user machines.

------------------------------------------------------------------------

## Cloud publishing definitions

ShareBridge can be published in two different ways:

-   **Local Windows distribution:** build a complete ShareBridge
    deployment folder or zip for SharePoint, OneDrive, or a file share.
    Users need the complete output, including `R/` when they do not have
    R installed.
-   **Hosted app or hosted inspector:** publish the app source to Posit
    Connect Cloud or a Docker-based Hugging Face Space. Users open a
    hosted URL. The hosted Publisher UI can upload an app folder, inspect
    it, run preflight checks, and return a generated zip, but it cannot
    browse arbitrary local paths or create Portable R from a local
    Windows R installation.

For the ShareBridge Publisher UI on Posit Connect Cloud, `app.R` is the
repository entry point and `manifest.json` must be committed. Regenerate
the manifest from the framework root after Publisher UI or docs changes:

``` r
files <- system2("git", "ls-files", stdout = TRUE)
files <- files[!files %in% c("manifest.json")]
files <- files[!grepl("^(R-portable|R-portable-master|\\.claude)/", files)]
rsconnect::writeManifest(
  appDir = ".",
  appFiles = files,
  appPrimaryDoc = "app.R",
  appMode = "shiny"
)
```

The Hugging Face Space lives at:

``` bash
git clone https://huggingface.co/spaces/Prigas89/Shiny_ShareBridge
```

It should remain a Docker Space that installs Shiny and launches
`build/publisher_ui/app.R` on port `7860`.

------------------------------------------------------------------------

## Known limitations

-   **OneDrive sync lag:** Users may launch before all files are synced.
    The app may fail with "package not found" until sync completes.
-   **Path length limits:** Deeply nested synced folders can hit
    Windows' 260-character path limit. Keep app folder names short.
-   **HTA restrictions:** Some environments block `.hta` files via Group
    Policy. Use `run.bat` as a fallback.
-   **Writable data in synced folders:** Frequently written app data
    should not live inside the synced deployment folder. Use a shared
    network drive path via `DATA_DIR` in `app_meta.cfg`.
-   **Pandoc not bundled automatically:** If your app needs Pandoc for
    PDF output, publishers must place Pandoc into the deployment
    `pandoc/` folder.

------------------------------------------------------------------------

## Possible future improvements

-   Custom app icon and branding in the launch window
-   Update notification against a central manifest
-   Standalone `.exe` publisher wrapper (no R needed on publisher
    machine)
-   Copy-to-SharePoint helper or post-build shortcut

------------------------------------------------------------------------

## License

ShareBridge is an internal deployment framework. If you bundle R and
CRAN packages, retain the applicable third-party license notices and
attribution requirements for redistributed components. R itself is
licensed under GPL-2 \| GPL-3.
