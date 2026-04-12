
# ShareBridge Publisher
#
# A local Shiny app that provides a visual interface for publishing
# portable Shiny app deployments. Replaces the command-line workflow.
#
# The build runs as a SEPARATE R subprocess to:
#   1. Avoid library path conflicts with this running Shiny app
#   2. Capture all console output reliably
#   3. Isolate the install.packages() calls completely
#
# Launch via publish.bat in the framework root.


library(shiny)


# Resolve framework directory -----------

resolve_framework_dir <- function() {
  candidates <- c(
    normalizePath(file.path("..", ".."), winslash = "/", mustWork = FALSE),
    normalizePath(".", winslash = "/", mustWork = FALSE)
  )
  for (d in candidates) {
    if (file.exists(file.path(d, "run.bat")) &&
        file.exists(file.path(d, "build", "build_packages.R"))) {
      return(normalizePath(d, winslash = "/", mustWork = TRUE))
    }
  }
  env_dir <- Sys.getenv("SHAREBRIDGE_FRAMEWORK_DIR", unset = "")
  if (nzchar(env_dir) && dir.exists(env_dir)) {
    return(normalizePath(env_dir, winslash = "/", mustWork = TRUE))
  }
  stop("Cannot locate ShareBridge framework directory.")
}


# Source publish_app.R for detect_dependencies only-----------

load_publisher <- function(framework_dir) {
  publish_script <- file.path(framework_dir, "build", "publish_app.R")
  if (!file.exists(publish_script)) stop("publish_app.R not found at: ", publish_script)
  env <- new.env(parent = globalenv())
  sys.source(publish_script, envir = env)
  env
}


# Find Rscript executable----------------

find_rscript <- function(framework_dir) {
  candidates <- c(
    file.path(framework_dir, "R-portable", "bin", "Rscript.exe"),
    file.path(framework_dir, "R-portable", "bin", "x64", "Rscript.exe"),
    Sys.which("Rscript")
  )
  hits <- candidates[file.exists(candidates)]
  if (length(hits)) return(normalizePath(hits[1], winslash = "/"))
  NULL
}

#css for app------------
css_app <- tags$head(
  tags$style(HTML("
      body {
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        background: #f7f8fa;
        color: #1a1a1a;
        max-width: 780px;
        margin: 0 auto;
        padding: 24px 16px;
      }
      .header {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        margin-bottom: 28px;
        padding-bottom: 16px;
        border-bottom: 1px solid #e2e4e8;
      }
      .header h2 {
        margin: 0 0 4px;
        font-weight: 600;
        font-size: 22px;
        letter-spacing: -0.3px;
      }
      .header p {
        margin: 0;
        color: #6b7280;
        font-size: 14px;
      }
      .btn-clear {
        padding: 6px 14px;
        font-size: 13px;
        background: #f3f4f6;
        border: 1px solid #d1d5db;
        border-radius: 6px;
        color: #374151;
        cursor: pointer;
        white-space: nowrap;
      }
      .btn-clear:hover { background: #e5e7eb; }
      .status-bar {
        display: flex;
        gap: 16px;
        margin-bottom: 24px;
        flex-wrap: wrap;
      }
      .status-item {
        display: flex;
        align-items: center;
        gap: 6px;
        font-size: 13px;
        color: #4b5563;
      }
      .dot {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        display: inline-block;
      }
      .dot-ok { background: #22c55e; }
      .dot-warn { background: #f59e0b; }
      .dot-err { background: #ef4444; }
      .card {
        background: #ffffff;
        border: 1px solid #e5e7eb;
        border-radius: 10px;
        padding: 20px 24px;
        margin-bottom: 16px;
      }
      .card h3 {
        margin: 0 0 14px;
        font-size: 15px;
        font-weight: 600;
        color: #111827;
      }
      .form-group { margin-bottom: 14px; }
      .form-group label {
        display: block;
        font-size: 13px;
        font-weight: 500;
        color: #374151;
        margin-bottom: 4px;
      }
      .form-group .help-text {
        font-size: 12px;
        color: #9ca3af;
        margin-top: 2px;
      }
      .path-row {
        display: flex;
        gap: 8px;
        align-items: stretch;
      }
      .path-row .form-control {
        flex: 1;
        font-family: 'Consolas', 'Courier New', monospace;
        font-size: 13px;
      }
      .btn-browse {
        white-space: nowrap;
        padding: 6px 14px;
        font-size: 13px;
        background: #f3f4f6;
        border: 1px solid #d1d5db;
        border-radius: 6px;
        color: #374151;
        cursor: pointer;
      }
      .btn-browse:hover { background: #e5e7eb; }
      .btn-build {
        width: 100%;
        padding: 12px;
        font-size: 15px;
        font-weight: 600;
        background: #2563eb;
        color: #ffffff;
        border: none;
        border-radius: 8px;
        cursor: pointer;
        transition: background 0.15s;
      }
      .btn-build:hover { background: #1d4ed8; }
      .btn-build:disabled {
        background: #93c5fd;
        cursor: not-allowed;
      }
      .btn-log {
        padding: 8px 14px;
        font-size: 13px;
        background: #f3f4f6;
        border: 1px solid #d1d5db;
        border-radius: 6px;
        color: #374151;
        cursor: pointer;
      }
      .btn-log:hover { background: #e5e7eb; }
      .btn-log-danger {
        padding: 8px 14px;
        font-size: 13px;
        background: #fef2f2;
        border: 1px solid #fecaca;
        border-radius: 6px;
        color: #991b1b;
        cursor: pointer;
      }
      .btn-log-danger:hover { background: #fee2e2; }
      .pkg-list {
        font-family: 'Consolas', 'Courier New', monospace;
        font-size: 13px;
        background: #f9fafb;
        border: 1px solid #e5e7eb;
        border-radius: 6px;
        padding: 10px 14px;
        color: #374151;
        min-height: 36px;
        line-height: 1.6;
      }
      .pkg-count {
        font-size: 12px;
        color: #6b7280;
        margin-top: 4px;
      }
      .log-output {
        font-family: 'Consolas', 'Courier New', monospace;
        font-size: 12px;
        background: #111827;
        color: #d1d5db;
        border-radius: 8px;
        padding: 14px 16px;
        max-height: 360px;
        overflow-y: auto;
        white-space: pre-wrap;
        word-break: break-word;
        line-height: 1.5;
      }
      .log-preview {
        font-family: 'Consolas', 'Courier New', monospace;
        font-size: 12px;
        background: #0f172a;
        color: #d1d5db;
        border-radius: 8px;
        padding: 14px 16px;
        max-height: 320px;
        overflow-y: auto;
        white-space: pre-wrap;
        word-break: break-word;
        line-height: 1.5;
        border: 1px solid #1f2937;
      }
      .log-meta {
        font-size: 12px;
        color: #6b7280;
        margin-top: 8px;
      }
      .log-error { color: #fca5a5; }
      .log-ok { color: #86efac; }
      .result-bar {
        display: flex;
        gap: 12px;
        align-items: center;
        padding: 14px 18px;
        border-radius: 8px;
        margin-top: 16px;
      }
      .result-bar.success {
        background: #f0fdf4;
        border: 1px solid #bbf7d0;
      }
      .result-bar.error {
        background: #fef2f2;
        border: 1px solid #fecaca;
      }
      .result-info {
        flex: 1;
        font-size: 13px;
      }
      .result-bar.success .result-info { color: #166534; }
      .result-bar.error .result-info { color: #991b1b; }
      .build-overlay {
        position: fixed;
        top: 0; left: 0; right: 0; bottom: 0;
        background: rgba(248,250,252,0.92);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 9999;
        backdrop-filter: blur(2px);
      }
      .overlay-card {
        background: #ffffff;
        border: 1px solid #e2e8f0;
        border-radius: 18px;
        padding: 44px 52px;
        max-width: 500px;
        width: 92%;
        text-align: center;
        box-shadow: 0 8px 40px rgba(15,23,42,0.12);
      }
      .overlay-pct {
        font-size: 48px;
        font-weight: 700;
        color: #1e293b;
        line-height: 1;
        letter-spacing: -1px;
        margin-bottom: 6px;
      }
      .overlay-pct span { font-size: 28px; color: #64748b; font-weight: 500; }
      .progress-bar-track {
        width: 100%;
        height: 8px;
        background: #e5e7eb;
        border-radius: 999px;
        overflow: hidden;
        margin: 14px 0 18px;
      }
      .progress-bar-fill {
        height: 100%;
        background: #2563eb;
        border-radius: 999px;
        transition: width 0.5s ease;
        min-width: 6px;
      }
      .progress-bar-fill.phase-compiling {
        background: linear-gradient(90deg, #2563eb, #7c3aed, #2563eb);
        background-size: 200% 100%;
        animation: shimmer-bar 2s linear infinite;
      }
      .progress-bar-fill.phase-done { background: #16a34a; }
      @keyframes shimmer-bar {
        0%   { background-position: 200% 0; }
        100% { background-position: -200% 0; }
      }
      .overlay-step {
        font-size: 15px;
        font-weight: 600;
        color: #111827;
        margin-bottom: 6px;
      }
      .overlay-detail {
        font-size: 12px;
        color: #6b7280;
        font-family: 'Consolas', 'Courier New', monospace;
        max-width: 380px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        margin: 0 auto 4px;
      }
      .overlay-elapsed {
        font-size: 12px;
        color: #9ca3af;
        margin-top: 10px;
      }
      .toolbar-row {
        display: flex;
        gap: 8px;
        align-items: center;
        flex-wrap: wrap;
        margin-top: 8px;
      }

      .btn-secondary {
      width: 100%;
      padding: 12px;
      font-size: 15px;
      font-weight: 600;
      background: #374151;
      color: #ffffff;
      border: none;
      border-radius: 8px;
      cursor: pointer;
      transition: background 0.15s;
    }
    .btn-secondary:hover { background: #1f2937; }
    .btn-secondary:disabled {
      background: #9ca3af;
      cursor: not-allowed;
    }
    "))
)


css_collapsible <- tags$style(HTML("
  .collapsible-card {
    background: #ffffff;
    border: 1px solid #e5e7eb;
    border-radius: 14px;
    padding: 0;
    margin-bottom: 18px;
    box-shadow: 0 2px 8px rgba(15, 23, 42, 0.05);
    overflow: hidden;
  }

  .collapsible-card summary {
    list-style: none;
    cursor: pointer;
    padding: 16px 18px;
    font-weight: 700;
    font-size: 16px;
    color: #111827;
    display: flex;
    align-items: center;
    justify-content: space-between;
    user-select: none;
  }

  .collapsible-card summary::-webkit-details-marker {
    display: none;
  }

  .collapsible-card summary::after {
    content: '+';
    font-size: 22px;
    line-height: 1;
    color: #6b7280;
    transition: transform 0.15s ease, color 0.15s ease;
  }

  .collapsible-card[open] summary::after {
    content: '−';
    color: #374151;
  }

  .collapsible-card summary:hover {
    background: #f9fafb;
  }

  .collapsible-body {
    padding: 0 18px 18px 18px;
    border-top: 1px solid #f1f5f9;
  }

  .section-stack {
    display: flex;
    flex-direction: column;
    gap: 18px;
  }

  .inline-checks {
    display: flex;
    gap: 24px;
    flex-wrap: wrap;
    margin-top: 6px;
  }

  .build-action-wrap {
    margin: 20px 0;
  }

  .muted-section-note {
    color: #6b7280;
    font-size: 13px;
    margin-top: 2px;
  }

  .sub-option-block {
    margin-top: 12px;
    padding: 14px;
    border: 1px solid #e5e7eb;
    border-radius: 10px;
    background: #f9fafb;
  }

  .sub-option-title {
    font-weight: 600;
    margin-bottom: 10px;
    color: #111827;
  }

  .folder-picker {
  margin-top: 8px;
}

.folder-picker .checkbox {
  margin-top: 8px;
  margin-bottom: 8px;
}

.folder-picker-empty {
  padding: 10px 12px;
  border: 1px dashed #d1d5db;
  border-radius: 10px;
  background: #ffffff;
  color: #6b7280;
  font-size: 13px;
}
"))

css_features <- tags$style(HTML("
  .validation-badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    padding: 4px 10px;
    border-radius: 20px;
    margin-top: 6px;
  }
  .validation-ok  { background: #f0fdf4; color: #166534; border: 1px solid #bbf7d0; }
  .validation-err { background: #fef2f2; color: #991b1b; border: 1px solid #fecaca; }
  .validation-warn{ background: #fffbeb; color: #92400e; border: 1px solid #fde68a; }

  .summary-panel {
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 10px;
    padding: 16px 20px;
    margin-bottom: 16px;
  }
  .summary-panel h4 {
    margin: 0 0 12px;
    font-size: 13px;
    font-weight: 600;
    color: #475569;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .summary-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px 24px;
  }
  .summary-row {
    display: flex;
    align-items: center;
    gap: 7px;
    font-size: 13px;
    color: #374151;
  }
  .summary-row .dot { flex-shrink: 0; }
  .summary-label { color: #6b7280; min-width: 110px; }
  .summary-value { font-weight: 500; color: #111827; }

  .health-list {
    margin: 10px 0 0;
    display: flex;
    flex-direction: column;
    gap: 5px;
  }
  .health-item {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    font-size: 13px;
    padding: 5px 10px;
    border-radius: 6px;
    background: #f9fafb;
  }
  .health-item.hc-ok   { background: #f0fdf4; color: #166534; }
  .health-item.hc-warn { background: #fffbeb; color: #92400e; }
  .health-item.hc-fail { background: #fef2f2; color: #991b1b; }
  .health-detail { font-size: 11px; margin-top: 2px; color: #6b7280; }
  .hc-header {
    font-size: 13px;
    font-weight: 600;
    margin: 12px 0 4px;
    color: #374151;
  }

  .profile-row {
    display: flex;
    gap: 8px;
    align-items: stretch;
    margin-top: 10px;
  }
  .profile-status {
    font-size: 12px;
    margin-top: 6px;
    padding: 4px 10px;
    border-radius: 6px;
  }
  .profile-status.ok  { background: #f0fdf4; color: #166534; }
  .profile-status.err { background: #fef2f2; color: #991b1b; }

  .btn-test-launch {
    padding: 8px 16px;
    font-size: 13px;
    font-weight: 500;
    background: #0d9488;
    color: #ffffff;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    transition: background 0.15s;
    white-space: nowrap;
  }
  .btn-test-launch:hover { background: #0f766e; }
"))

# UI---------------------------

ui <- fluidPage(
  css_app,
  css_collapsible,
  css_features,

  div(class = "header",
      div(
        h2("ShareBridge Publisher"),
        p("Build portable Shiny app deployments")
      ),
      uiOutput("clear_button_ui")
  ),

  uiOutput("build_overlay"),
  uiOutput("status_bar"),

  div(class = "section-stack",

      # Main publishing flow
      div(class = "card",
          h3("Source app"),
          div(class = "form-group",
              tags$label("App folder"),
              div(class = "path-row",
                  textInput(
                    "source_dir",
                    label = NULL,
                    value = "",
                    width = "100%",
                    placeholder = "C:\\Users\\you\\projects\\my_shiny_app"
                  ),
                  actionButton("browse_source", "Browse", class = "btn-browse")
              ),
              div(
                class = "help-text",
                "Folder containing app.R or ui.R + server.R, plus any supporting files such as www, modules, R, data, or config"
              ),
              uiOutput("source_validation_ui")
          ),
          div(class = "form-group",
              textInput(
                "app_name",
                "App name",
                value = "",
                placeholder = "My Dashboard"
              ),
              div(
                class = "help-text",
                "Used for display name, port derivation, and folder naming"
              )
          )
      ),

      div(class = "card",
          h3("Detected packages"),
          uiOutput("detected_packages"),
          div(class = "form-group", style = "margin-top: 14px;",
              textAreaInput(
                "extra_packages",
                "Additional packages (one per line, optional)",
                value = "",
                rows = 3,
                resize = "vertical",
                placeholder = "arrow\njanitor"
              ),
              div(
                class = "help-text",
                "Add packages that the scanner might miss (dynamic loading, etc.)"
              )
          )
      ),

      div(class = "card",
          h3("Output"),
          div(class = "form-group",
              tags$label("Output folder"),
              div(class = "path-row",
                  textInput(
                    "output_dir",
                    label = NULL,
                    value = "",
                    width = "100%",
                    placeholder = "C:\\Users\\you\\Documents\\MyApp_deploy"
                  ),
                  actionButton("browse_output", "Browse", class = "btn-browse")
              )
          ),
          div(class = "inline-checks",
              checkboxInput("zip_output", "Create zip file", value = TRUE),
              checkboxInput("build_offline_repo", "Build offline repo", value = FALSE)
          )
      ),

      # Advanced app features
      tags$details(
        class = "collapsible-card",
        tags$summary(HTML("<span>Advanced app features</span>")),
        div(class = "collapsible-body",
            div(class = "muted-section-note",
                "Optional features for apps that need extra runtime support."
            ),

            div(class = "inline-checks",
                checkboxInput("enable_write_mode", "Enable write-capable app mode", value = FALSE),
                checkboxInput("include_pandoc", "Include Pandoc runtime", value = FALSE)
            ),

            conditionalPanel(
              condition = "input.enable_write_mode",
              div(class = "sub-option-block",
                  div(class = "sub-option-title", "Write-capable app settings"),
                  uiOutput("writable_dirs_ui"),
                  div(
                    class = "help-text",
                    "Select app folders that should remain writable in the deployed app"
                  )
              )
            ),

            conditionalPanel(
              condition = "input.include_pandoc",
              div(class = "sub-option-block",
                  div(class = "sub-option-title", "Pandoc support"),
                  checkboxInput("bundle_rmarkdown_support", "Include rmarkdown-related helpers", value = TRUE),
                  div(
                    class = "help-text",
                    "Enable this for apps that render reports or downloadable documents"
                  )
              )
            ),

            div(class = "form-group", style = "margin-top: 14px;",
                tags$label("External data directory (DATA_DIR) — optional"),
                textInput(
                  "data_dir",
                  label = NULL,
                  value = "",
                  width = "100%",
                  placeholder = "\\\\server\\share\\AppData  or  C:\\SharedData\\MyApp"
                ),
                div(
                  class = "help-text",
                  "Written to app_meta.cfg as DATA_DIR. At runtime ShareBridge sets SHAREBRIDGE_DATA_DIR. Use for app data that should live outside the synced deployment folder."
                )
            )
        )
      ),

      # Saved profiles
      tags$details(
        class = "collapsible-card",
        tags$summary(HTML("<span>Saved profiles</span>")),
        div(class = "collapsible-body",
            div(class = "muted-section-note",
                "Save your current build settings and reload them for future builds."
            ),
            div(class = "profile-row",
                textInput(
                  "profile_name_input",
                  label = NULL,
                  value = "",
                  width = "100%",
                  placeholder = "Profile name (e.g. My Dashboard - prod)"
                ),
                actionButton("save_profile", "Save", class = "btn-browse")
            ),
            div(class = "form-group", style = "margin-top: 12px;",
                selectInput(
                  "profile_select",
                  "Saved profiles",
                  choices = character(0),
                  width = "100%"
                )
            ),
            div(class = "toolbar-row",
                actionButton("load_profile", "Load selected", class = "btn-log"),
                actionButton("delete_profile", "Delete selected", class = "btn-log-danger")
            ),
            uiOutput("profile_status_ui")
        )
      ),

      # Framework setup
      tags$details(
        class = "collapsible-card",
        tags$summary(
          HTML("<span>Framework setup</span>")
        ),
        div(class = "collapsible-body",
            div(class = "muted-section-note",
                "Create or manage the portable R framework used for deployment."
            ),
            div(class = "form-group", style = "margin-top: 14px;",
                tags$label("Full R installation folder"),
                div(class = "path-row",
                    textInput(
                      "r_source_dir",
                      label = NULL,
                      value = "",
                      width = "100%",
                      placeholder = "C:\\Users\\you\\R-build\\R-4.3.2"
                    ),
                    actionButton("browse_r_source", "Browse", class = "btn-browse")
                ),
                div(
                  class = "help-text",
                  "Select a full R installation to create R-portable for ShareBridge"
                )
            ),
            div(class = "inline-checks",
                checkboxInput("keep_tcltk", "Keep Tcl/Tk runtime", value = FALSE),
                checkboxInput("strip_pkg_docs", "Strip package docs", value = TRUE)
            ),
            div(style = "margin-top: 12px;",
                uiOutput("strip_r_button_ui")
            ),
            uiOutput("strip_r_result"),
            uiOutput("strip_r_log_section")
        )
      ),

      # Saved logs
      tags$details(
        class = "collapsible-card",
        tags$summary(
          HTML("<span>Publisher logs</span>")
        ),
        div(class = "collapsible-body",
            div(class = "muted-section-note",
                "Browse, preview, and remove saved publisher log files."
            ),
            div(class = "form-group", style = "margin-top: 14px;",
                selectInput(
                  "selected_log_file",
                  "Available log files",
                  choices = character(0),
                  width = "100%"
                ),
                div(
                  class = "help-text",
                  "View or delete stored publisher log files"
                )
            ),
            div(class = "toolbar-row",
                actionButton("refresh_logs", "Refresh list", class = "btn-log"),
                actionButton("view_log", "View selected log", class = "btn-log"),
                actionButton("delete_log", "Delete selected log", class = "btn-log-danger"),
                actionButton("delete_all_logs", "Delete all logs", class = "btn-log-danger")
            ),
            uiOutput("selected_log_meta"),
            uiOutput("selected_log_preview")
        )
      ),

      # Live log
      tags$details(
        class = "collapsible-card",
        tags$summary(
          HTML("<span>Current build log</span>")
        ),
        div(class = "collapsible-body",
            div(class = "muted-section-note",
                "Expanded live output for the current or most recent build."
            ),
            div(style = "margin-top: 14px;",
                uiOutput("log_section")
            )
        )
      )
  ),

  uiOutput("build_summary"),

  div(class = "build-action-wrap",
      uiOutput("build_button_ui")
  ),

  uiOutput("build_result"),
  uiOutput("health_check_ui")
)



# Server -----------------------------------------------------------

server <- function(input, output, session) {

  # Reactive state --------
  rv <- reactiveValues(
    framework_dir = NULL,
    publisher_env = NULL,
    rscript_path = NULL,
    build_rscript_path = NULL,
    detected_pkgs = character(0),
    building = FALSE,
    build_done = FALSE,
    build_success = FALSE,
    build_error = NULL,
    log_lines = character(0),
    output_path = NULL,
    zip_path = NULL,
    build_proc = NULL,
    build_log_file = NULL,
    build_start_time = NULL,
    req_extra_file = NULL,
    app_features_file = NULL,
    selected_log_lines = character(0),
    selected_log_path = NULL,
    temp_bat_file = NULL,
    strip_r_running = FALSE,
    strip_r_done = FALSE,
    strip_r_success = FALSE,
    strip_r_error = NULL,
    strip_r_log_lines = character(0),
    strip_r_proc = NULL,
    strip_r_log_file = NULL,
    strip_r_bat_file = NULL,
    # source validation
    source_valid = FALSE,
    source_validation_msg = "",
    # health check
    health_check_results = NULL,
    # profiles
    profiles_dir = NULL
  )

  # Session cleanup --------
  session$onSessionEnded(function() {
    build_proc <- isolate(rv$build_proc)
    strip_r_proc <- isolate(rv$strip_r_proc)
    req_extra_file <- isolate(rv$req_extra_file)
    app_features_file <- isolate(rv$app_features_file)
    temp_bat_file <- isolate(rv$temp_bat_file)
    strip_r_bat_file <- isolate(rv$strip_r_bat_file)

    if (!is.null(build_proc)) {
      try(build_proc$kill(), silent = TRUE)
    }
    if (!is.null(strip_r_proc)) {
      try(strip_r_proc$kill(), silent = TRUE)
    }
    if (!is.null(req_extra_file) && file.exists(req_extra_file)) {
      try(unlink(req_extra_file), silent = TRUE)
    }
    if (!is.null(app_features_file) && file.exists(app_features_file)) {
      try(unlink(app_features_file), silent = TRUE)
    }
    if (!is.null(temp_bat_file) && file.exists(temp_bat_file)) {
      try(unlink(temp_bat_file), silent = TRUE)
    }
    if (!is.null(strip_r_bat_file) && file.exists(strip_r_bat_file)) {
      try(unlink(strip_r_bat_file), silent = TRUE)
    }

  })


  #safe build R helper--------------
  find_build_rscript <- function(framework_dir) {
    portable_candidates <- c(
      file.path(framework_dir, "R-portable", "bin", "Rscript.exe"),
      file.path(framework_dir, "R-portable", "bin", "x64", "Rscript.exe"),
      file.path(framework_dir, "R-portable-master", "bin", "Rscript.exe"),
      file.path(framework_dir, "R-portable-master", "bin", "x64", "Rscript.exe")
    )
    portable_candidates <- normalizePath(
      portable_candidates,
      winslash = "/",
      mustWork = FALSE
    )

    pf_r <- "C:/Program Files/R"
    pf_candidates <- character(0)

    if (dir.exists(pf_r)) {
      r_dirs <- list.dirs(pf_r, full.names = TRUE, recursive = FALSE)
      pf_candidates <- c(
        file.path(r_dirs, "bin", "Rscript.exe"),
        file.path(r_dirs, "bin", "x64", "Rscript.exe")
      )
    }

    candidates <- c(
      Sys.which("Rscript"),
      pf_candidates
    )

    candidates <- unique(candidates[nzchar(candidates)])
    candidates <- candidates[file.exists(candidates)]

    if (!length(candidates)) {
      stop(
        paste(
          "No external Rscript.exe found.",
          "Please install R or configure a build Rscript outside framework_dir/R-portable and framework_dir/R-portable-master."
        )
      )
    }

    candidates_norm <- normalizePath(candidates, winslash = "/", mustWork = FALSE)
    keep <- !candidates_norm %in% portable_candidates
    candidates <- candidates[keep]

    if (!length(candidates)) {
      stop(
        paste(
          "No safe external Rscript.exe found.",
          "The only Rscript detected belongs to framework_dir/R-portable or framework_dir/R-portable-master, which cannot be used to publish while copying portable R."
        )
      )
    }

    normalizePath(candidates[1], winslash = "/", mustWork = TRUE)
  }

  # Log directory helpers --------
  publisher_log_dir <- function() {
    req(rv$framework_dir)
    dir <- file.path(rv$framework_dir, "logs", "publisher")
    if (!dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    normalizePath(dir, winslash = "/", mustWork = TRUE)
  }

  new_publisher_log_file <- function(prefix = "publish") {
    log_dir <- publisher_log_dir()
    stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    file.path(log_dir, paste0(prefix, "_", stamp, ".log"))
  }

  cleanup_old_publisher_logs <- function(days = 30) {
    if (is.null(rv$framework_dir) || !dir.exists(rv$framework_dir)) return(invisible(NULL))
    log_dir <- file.path(rv$framework_dir, "logs", "publisher")
    if (!dir.exists(log_dir)) return(invisible(NULL))

    files <- list.files(log_dir, pattern = "\\.log$", full.names = TRUE)
    if (!length(files)) return(invisible(NULL))

    info <- file.info(files)
    cutoff <- Sys.time() - (days * 24 * 60 * 60)
    old_files <- rownames(info)[!is.na(info$mtime) & info$mtime < cutoff]
    if (length(old_files)) unlink(old_files, force = TRUE)
    invisible(NULL)
  }

  list_publisher_logs <- function() {
    if (is.null(rv$framework_dir) || !dir.exists(rv$framework_dir)) return(character(0))
    log_dir <- file.path(rv$framework_dir, "logs", "publisher")
    if (!dir.exists(log_dir)) return(character(0))

    files <- list.files(log_dir, pattern = "\\.log$", full.names = TRUE)
    if (!length(files)) return(character(0))

    info <- file.info(files)
    files[order(info$mtime, decreasing = TRUE)]
  }

  log_choices_named <- function() {
    files <- list_publisher_logs()
    if (!length(files)) return(setNames(character(0), character(0)))

    info <- file.info(files)
    labels <- paste0(
      basename(files), "  |  ",
      format(info$mtime, "%Y-%m-%d %H:%M"), "  |  ",
      format(round(info$size / 1024, 1), nsmall = 1), " KB"
    )
    stats::setNames(files, labels)
  }

  refresh_log_choices <- function(select_latest = TRUE) {
    choices <- log_choices_named()
    updateSelectInput(session, "selected_log_file",
                      choices = choices,
                      selected = if (length(choices) && isTRUE(select_latest)) unname(choices[[1]]) else character(0)
    )
    if (!length(choices)) {
      rv$selected_log_path <- NULL
      rv$selected_log_lines <- character(0)
    }
  }

  read_selected_log <- function(path, tail_lines = 250) {
    if (is.null(path) || !nzchar(path) || !file.exists(path)) return(character(0))
    lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character(0))
    if (length(lines) > tail_lines) lines <- tail(lines, tail_lines)
    lines
  }

  # Strip R helpers --------
  read_strip_r_log <- function() {
    if (is.null(rv$strip_r_log_file) || !file.exists(rv$strip_r_log_file)) return(character(0))
    tryCatch(readLines(rv$strip_r_log_file, warn = FALSE), error = function(e) character(0))
  }

  portable_r_exists <- reactive({
    !is.null(rv$framework_dir) && (
      dir.exists(file.path(rv$framework_dir, "R-portable-master")) ||
        dir.exists(file.path(rv$framework_dir, "R-portable"))
    )
  })

  can_strip_r <- reactive({
    !rv$strip_r_running &&
      !is.null(rv$framework_dir) &&
      nzchar(input$r_source_dir %||% "") &&
      dir.exists(input$r_source_dir %||% "") &&
      !is.null(rv$build_rscript_path)
  })

  # Build progress parser --------
  parse_build_progress <- function(log_lines) {
    blank <- list(pct = 2, phase = "init", label = "Initializing...", detail = "")
    if (!length(log_lines)) return(blank)

    has  <- function(pat) any(grepl(pat, log_lines, fixed = TRUE))
    last <- function(pat, fixed = FALSE) {
      hits <- grep(pat, log_lines, value = TRUE, perl = !fixed, fixed = fixed)
      if (length(hits)) tail(hits, 1) else ""
    }

    if (has("[publish] Done."))
      return(list(pct = 100, phase = "done", label = "Build complete", detail = ""))
    if (has("[build] Wrote manifest:"))
      return(list(pct = 96, phase = "manifest", label = "Finalizing deployment...", detail = ""))
    if (has("Load verification OK"))
      return(list(pct = 92, phase = "verify", label = "Verifying packages load correctly...", detail = ""))
    if (has("[build] Verifying package loadability"))
      return(list(pct = 88, phase = "verify", label = "Verifying packages...", detail = ""))

    # Source compilation — detect [N%] lines in recent output
    recent <- tail(log_lines, 50)
    src_pct_lines <- grep("^\\[\\s*\\d+%\\]", recent, value = TRUE, perl = TRUE)
    if (length(src_pct_lines)) {
      src_pct <- as.integer(sub("^\\[\\s*(\\d+)%\\].*", "\\1", tail(src_pct_lines, 1)))
      pkg_line <- last("installing \\*source\\* package '([^']+)'")
      pkg_name <- if (nzchar(pkg_line)) sub(".*'([^']+)'.*", "\\1", pkg_line) else "package"
      src_list_line <- last("installing the source packages", fixed = TRUE)
      n_src <- if (nzchar(src_list_line)) {
        length(strsplit(gsub("['\"]", "", sub("installing the source packages ", "", src_list_line)), ",\\s*")[[1]])
      } else 1L
      n_src_done <- length(grep("^\\* DONE \\(", recent, perl = TRUE))
      per_pkg <- 25L / max(n_src, 1L)
      scaled <- as.integer(60 + n_src_done * per_pkg + (src_pct / 100) * per_pkg)
      scaled <- max(60L, min(85L, scaled))
      return(list(
        pct    = scaled,
        phase  = "compiling",
        label  = sprintf("Compiling %s from source... (%d%%)", pkg_name, src_pct),
        detail = "Source compilation is slower — this is a one-time cost for this version"
      ))
    }

    # Binary package install / download
    n_done <- length(grep("successfully unpacked and MD5 sums checked|successfully installed",
                          log_lines, fixed = FALSE, perl = TRUE))
    if (has("[build] Installing missing packages") || n_done > 0L) {
      req_line  <- last("\\[build\\] Requested packages:\\s*(\\d+)")
      n_req     <- if (nzchar(req_line)) as.integer(sub(".*:\\s*", "", req_line)) else 0L
      dep_line  <- last("also installing the dependencies", fixed = TRUE)
      n_deps    <- if (nzchar(dep_line)) {
        length(strsplit(gsub("['\"]", "", sub("also installing the dependencies ", "", dep_line)), ",\\s*")[[1]])
      } else 0L
      src_line  <- last("installing the source packages", fixed = TRUE)
      n_src_tot <- if (nzchar(src_line)) {
        length(strsplit(gsub("['\"]", "", sub("installing the source packages ", "", src_line)), ",\\s*")[[1]])
      } else 0L
      n_total   <- n_req + n_deps + n_src_tot

      if (n_total > 0L) {
        pct   <- as.integer(35 + (n_done / n_total) * 50)
        pct   <- min(pct, 82L)
        label <- sprintf("Installing packages (%d of %d)...", n_done, n_total)
      } else {
        pct   <- if (n_done > 0L) min(40L + n_done * 2L, 60L) else 38L
        label <- if (n_done > 0L) sprintf("Installing packages (%d done)...", n_done) else "Downloading packages..."
      }

      # Friendly detail line
      detail_raw <- last("trying URL|successfully unpacked|successfully installed")
      detail <- if (nzchar(detail_raw)) {
        detail_raw <- sub("trying URL '.*/(.*\\.zip)'$", "Downloading \\1...", detail_raw)
        detail_raw <- sub("package '([^']+)' successfully (unpacked|installed).*", "\u2713 \\1", detail_raw)
        trimws(detail_raw)
      } else ""
      return(list(pct = pct, phase = "installing", label = label, detail = detail))
    }

    if (has("[publish] Building bundled package library"))
      return(list(pct = 32, phase = "building", label = "Preparing package library...", detail = ""))
    if (has("[publish] req.txt written")) {
      pkg_detail <- last("\\[publish\\] Packages:")
      pkg_detail <- trimws(sub("\\[publish\\] Packages:\\s*", "", pkg_detail))
      return(list(pct = 26, phase = "deps", label = "Dependencies detected", detail = pkg_detail))
    }
    if (has("[copy] robocopy"))
      return(list(pct = 18, phase = "copy_r", label = "Copying portable R...", detail = ""))
    if (has("[publish] Portable R source:"))
      return(list(pct = 12, phase = "copy_r", label = "Locating portable R...", detail = ""))
    if (has("[publish] Output dir reset complete"))
      return(list(pct = 10, phase = "setup", label = "Setting up output folder...", detail = ""))
    if (has("[ui] Starting background build process"))
      return(list(pct = 5, phase = "start", label = "Build started...", detail = ""))

    blank
  }

  # Build helpers --------
  append_log_lines <- function(lines) {
    lines <- as.character(lines)
    lines <- lines[nzchar(lines)]
    if (!length(lines)) return(invisible(NULL))
    rv$log_lines <- c(rv$log_lines, lines)
    invisible(NULL)
  }

  read_build_log <- function() {
    if (is.null(rv$build_log_file) || !file.exists(rv$build_log_file)) return(character(0))
    tryCatch(readLines(rv$build_log_file, warn = FALSE), error = function(e) character(0))
  }

  cleanup_temp_files <- function() {
    if (!is.null(rv$req_extra_file) && file.exists(rv$req_extra_file)) {
      try(unlink(rv$req_extra_file), silent = TRUE)
    }
    rv$req_extra_file <- NULL

    if (!is.null(rv$app_features_file) && file.exists(rv$app_features_file)) {
      try(unlink(rv$app_features_file), silent = TRUE)
    }
    rv$app_features_file <- NULL

    if (!is.null(rv$temp_bat_file) && file.exists(rv$temp_bat_file)) {
      try(unlink(rv$temp_bat_file), silent = TRUE)
    }
    rv$temp_bat_file <- NULL
  }

  finalize_build <- function(exit_code) {
    rv$building <- FALSE
    rv$build_done <- TRUE
    rv$build_success <- identical(as.integer(exit_code), 0L)

    latest_log <- read_build_log()
    if (length(latest_log)) rv$log_lines <- latest_log

    if (rv$build_success) {
      rv$output_path <- normalizePath(input$output_dir, winslash = "/", mustWork = FALSE)
      zip_candidate <- paste0(rv$output_path, ".zip")
      rv$zip_path <- if (file.exists(zip_candidate)) zip_candidate else NULL
      rv$build_error <- NULL
    } else {
      error_lines <- grep(
        "Error|error|FAIL|stop|missing|cannot|failed",
        rv$log_lines, value = TRUE, ignore.case = TRUE
      )
      rv$build_error <- if (length(error_lines)) {
        paste(tail(error_lines, 5), collapse = "\n")
      } else {
        paste("Build exited with code", exit_code)
      }
    }

    cleanup_temp_files()

    if (!is.null(rv$build_proc)) try(rv$build_proc$kill(), silent = TRUE)
    rv$build_proc <- NULL
    refresh_log_choices(select_latest = TRUE)

    if (rv$build_success && !is.null(rv$output_path)) {
      rv$health_check_results <- run_health_check(rv$output_path)
    } else {
      rv$health_check_results <- NULL
    }
  }

  # App subdirectory discovery (for advanced features) --------
  app_subdirs <- reactive({
    src <- trimws(input$source_dir %||% "")
    if (!nzchar(src) || !dir.exists(src)) return(character(0))

    root <- normalizePath(src, winslash = "/", mustWork = TRUE)
    dirs <- list.dirs(root, full.names = FALSE, recursive = FALSE)
    if (!length(dirs)) return(character(0))

    excluded <- c(".git", ".github", ".Rproj.user", "renv", "packrat", "node_modules", "__pycache__")
    sort(unique(dirs[!dirs %in% excluded]))
  })

  # Profiles helpers --------
  profile_fields <- function() {
    list(
      source_dir             = trimws(input$source_dir %||% ""),
      app_name               = trimws(input$app_name %||% ""),
      output_dir             = trimws(input$output_dir %||% ""),
      extra_packages         = trimws(input$extra_packages %||% ""),
      zip_output             = isTRUE(input$zip_output),
      build_offline_repo     = isTRUE(input$build_offline_repo),
      enable_write_mode      = isTRUE(input$enable_write_mode),
      include_pandoc         = isTRUE(input$include_pandoc),
      bundle_rmarkdown_support = isTRUE(input$bundle_rmarkdown_support),
      data_dir               = trimws(input$data_dir %||% "")
    )
  }

  profile_path <- function(name) {
    safe <- gsub("[^A-Za-z0-9 _\\-]", "_", name)
    safe <- gsub("_+", "_", trimws(safe))
    file.path(rv$profiles_dir, paste0(safe, ".json"))
  }

  list_profiles <- function() {
    if (is.null(rv$profiles_dir) || !dir.exists(rv$profiles_dir)) return(character(0))
    files <- list.files(rv$profiles_dir, pattern = "\\.json$", full.names = FALSE)
    sort(sub("\\.json$", "", files))
  }

  refresh_profile_choices <- function() {
    choices <- list_profiles()
    updateSelectInput(session, "profile_select",
                      choices = if (length(choices)) choices else character(0),
                      selected = if (length(choices)) choices[1] else character(0))
  }

  observeEvent(input$save_profile, {
    name <- trimws(input$profile_name_input %||% "")
    if (!nzchar(name)) {
      output$profile_status_ui <- renderUI({
        div(class = "profile-status err", "Enter a profile name first.")
      })
      return()
    }
    if (is.null(rv$profiles_dir)) return()

    tryCatch({
      jsonlite::write_json(profile_fields(), path = profile_path(name),
                           auto_unbox = TRUE, pretty = TRUE)
      refresh_profile_choices()
      updateSelectInput(session, "profile_select", selected = name)
      output$profile_status_ui <- renderUI({
        div(class = "profile-status ok", paste0("Saved: ", name))
      })
    }, error = function(e) {
      output$profile_status_ui <- renderUI({
        div(class = "profile-status err", paste("Save failed:", conditionMessage(e)))
      })
    })
  })

  observeEvent(input$load_profile, {
    name <- input$profile_select %||% ""
    if (!nzchar(name) || is.null(rv$profiles_dir)) return()

    path <- profile_path(name)
    if (!file.exists(path)) {
      output$profile_status_ui <- renderUI({
        div(class = "profile-status err", "Profile file not found.")
      })
      return()
    }

    tryCatch({
      p <- jsonlite::read_json(path, simplifyVector = TRUE)
      if (!is.null(p$source_dir))  updateTextInput(session, "source_dir",  value = p$source_dir)
      if (!is.null(p$app_name))    updateTextInput(session, "app_name",    value = p$app_name)
      if (!is.null(p$output_dir))  updateTextInput(session, "output_dir",  value = p$output_dir)
      if (!is.null(p$extra_packages)) updateTextAreaInput(session, "extra_packages", value = p$extra_packages)
      if (!is.null(p$zip_output))             updateCheckboxInput(session, "zip_output",             value = isTRUE(p$zip_output))
      if (!is.null(p$build_offline_repo))     updateCheckboxInput(session, "build_offline_repo",     value = isTRUE(p$build_offline_repo))
      if (!is.null(p$enable_write_mode))      updateCheckboxInput(session, "enable_write_mode",      value = isTRUE(p$enable_write_mode))
      if (!is.null(p$include_pandoc))         updateCheckboxInput(session, "include_pandoc",         value = isTRUE(p$include_pandoc))
      if (!is.null(p$bundle_rmarkdown_support)) updateCheckboxInput(session, "bundle_rmarkdown_support", value = isTRUE(p$bundle_rmarkdown_support))
      if (!is.null(p$data_dir))    updateTextInput(session, "data_dir",    value = p$data_dir %||% "")
      output$profile_status_ui <- renderUI({
        div(class = "profile-status ok", paste0("Loaded: ", name))
      })
    }, error = function(e) {
      output$profile_status_ui <- renderUI({
        div(class = "profile-status err", paste("Load failed:", conditionMessage(e)))
      })
    })
  })

  observeEvent(input$delete_profile, {
    name <- input$profile_select %||% ""
    if (!nzchar(name) || is.null(rv$profiles_dir)) return()

    path <- profile_path(name)
    try(unlink(path, force = TRUE), silent = TRUE)
    refresh_profile_choices()
    output$profile_status_ui <- renderUI({
      div(class = "profile-status ok", paste0("Deleted: ", name))
    })
  })

  output$profile_status_ui <- renderUI({ NULL })

  # Health check helper --------
  run_health_check <- function(output_dir) {
    if (is.null(output_dir) || !dir.exists(output_dir)) return(NULL)

    results <- list()
    add_check <- function(id, label, ok, detail = NULL, critical = TRUE) {
      results[[id]] <<- list(label = label, ok = ok, detail = detail, critical = critical)
    }

    for (f in c("LaunchApp.hta", "run.bat", "run.R", "req.txt", "app_meta.cfg", "VERSION")) {
      add_check(paste0("f_", f), f, file.exists(file.path(output_dir, f)))
    }

    add_check("app_dir", "app/ directory", dir.exists(file.path(output_dir, "app")))

    pkg_dir  <- file.path(output_dir, "packages")
    req_file <- file.path(output_dir, "req.txt")
    add_check("packages_dir", "packages/ directory", dir.exists(pkg_dir))

    if (file.exists(req_file) && dir.exists(pkg_dir)) {
      req_pkgs <- trimws(readLines(req_file, warn = FALSE))
      req_pkgs <- req_pkgs[nzchar(req_pkgs) & !grepl("^#", req_pkgs)]
      installed_pkgs <- basename(list.dirs(pkg_dir, recursive = FALSE, full.names = FALSE))
      missing_pkgs <- setdiff(req_pkgs, installed_pkgs)
      detail <- if (length(missing_pkgs)) {
        paste("Missing:", paste(head(missing_pkgs, 5), collapse = ", "),
              if (length(missing_pkgs) > 5) paste0("… +", length(missing_pkgs) - 5, " more") else "")
      } else NULL
      add_check("pkgs_complete",
                sprintf("All %d required packages bundled", length(req_pkgs)),
                length(missing_pkgs) == 0, detail = detail)
    }

    add_check("portable_r", "Portable R bundled (R/)",
              dir.exists(file.path(output_dir, "R")), critical = FALSE)

    pandoc_dir <- file.path(output_dir, "pandoc")
    if (dir.exists(pandoc_dir)) {
      has_exe <- file.exists(file.path(pandoc_dir, "pandoc.exe"))
      add_check("pandoc_exe", "pandoc.exe present in pandoc/", has_exe,
                detail = if (!has_exe) "Pandoc stub folder exists but pandoc.exe not placed yet" else NULL,
                critical = FALSE)
    }

    results
  }

  output$health_check_ui <- renderUI({
    res <- rv$health_check_results
    if (is.null(res) || !length(res)) return(NULL)

    items <- lapply(res, function(chk) {
      cls <- if (isTRUE(chk$ok)) "hc-ok" else if (isTRUE(chk$critical)) "hc-fail" else "hc-warn"
      icon <- if (isTRUE(chk$ok)) "\u2713" else "\u2717"
      div(class = paste("health-item", cls),
          span(style = "font-weight:600; width:14px; flex-shrink:0;", icon),
          div(
            div(chk$label),
            if (!is.null(chk$detail)) div(class = "health-detail", chk$detail)
          )
      )
    })

    n_fail  <- sum(!vapply(res, function(x) isTRUE(x$ok) || !isTRUE(x$critical), logical(1)))
    n_warn  <- sum(!vapply(res, function(x) isTRUE(x$ok), logical(1))) - n_fail
    summary_cls <- if (n_fail > 0) "error" else "success"
    summary_msg <- if (n_fail > 0) {
      paste(n_fail, "critical issue(s) detected")
    } else if (n_warn > 0) {
      paste(n_warn, "warning(s) — review below")
    } else {
      "Deployment looks healthy"
    }

    div(
      div(class = paste("result-bar", summary_cls), style = "margin-top: 10px;",
          div(class = "result-info",
              strong("Health check: "), summary_msg)
      ),
      div(class = "health-list", do.call(tagList, items))
    )
  })

  # Test launch handler --------
  observeEvent(input$test_launch, {
    req(rv$build_success, !is.null(rv$output_path))
    launch_hta <- normalizePath(
      file.path(rv$output_path, "LaunchApp.hta"),
      winslash = "\\", mustWork = FALSE)
    if (file.exists(launch_hta)) {
      shell.exec(launch_hta)
    } else {
      run_bat <- normalizePath(
        file.path(rv$output_path, "run.bat"),
        winslash = "\\", mustWork = FALSE)
      if (file.exists(run_bat)) shell.exec(run_bat)
    }
  })

  # Build summary renderer --------
  output$build_summary <- renderUI({
    if (!can_build() || rv$building || rv$build_done) return(NULL)

    app_id_val <- gsub("[^A-Za-z0-9_]+", "_",
                       gsub("_+", "_", trimws(input$app_name %||% "")))
    app_id_val <- gsub("^_|_$", "", app_id_val)

    has_portable_r <- !is.null(rv$framework_dir) && (
      dir.exists(file.path(rv$framework_dir, "R-portable-master")) ||
        dir.exists(file.path(rv$framework_dir, "R-portable"))
    )

    extra_raw <- trimws(unlist(strsplit(input$extra_packages %||% "", "\n")))
    extra_pkgs <- unique(extra_raw[nzchar(extra_raw)])
    total_pkgs <- length(unique(c(rv$detected_pkgs, extra_pkgs)))

    make_row <- function(label, value, dot_cls = NULL) {
      div(class = "summary-row",
          if (!is.null(dot_cls)) span(class = paste("dot", dot_cls)),
          span(class = "summary-label", label),
          span(class = "summary-value", value)
      )
    }

    div(class = "summary-panel",
        tags$h4("Build summary"),
        div(class = "summary-grid",
            make_row("App name",    input$app_name),
            make_row("App ID",      if (nzchar(app_id_val)) app_id_val else "\u2014"),
            make_row("Packages",    paste(total_pkgs, "total")),
            make_row("Portable R",  if (has_portable_r) "bundled" else "not found",
                     if (has_portable_r) "dot-ok" else "dot-warn"),
            make_row("Zip output",  if (isTRUE(input$zip_output)) "yes" else "no"),
            make_row("Offline repo",if (isTRUE(input$build_offline_repo)) "yes" else "no"),
            make_row("Pandoc stub", if (isTRUE(input$include_pandoc)) "yes" else "no"),
            make_row("DATA_DIR",    {
              d <- trimws(input$data_dir %||% "")
              if (nzchar(d)) d else "(none)"
            })
        )
    )
  })

  # Initialize --------
  observeEvent(TRUE, {
    tryCatch({
      rv$framework_dir <- resolve_framework_dir()
      rv$publisher_env <- load_publisher(rv$framework_dir)
      rv$rscript_path <- find_rscript(rv$framework_dir)
      rv$build_rscript_path <- find_build_rscript(rv$framework_dir)
      rv$profiles_dir <- file.path(rv$framework_dir, "profiles")
      if (!dir.exists(rv$profiles_dir)) {
        dir.create(rv$profiles_dir, recursive = TRUE, showWarnings = FALSE)
      }
      refresh_profile_choices()
    }, error = function(e) {
      rv$framework_dir <- NULL
      rv$publisher_env <- NULL
      rv$rscript_path <- NULL
      rv$build_rscript_path <- NULL
      rv$build_error <- conditionMessage(e)
    })
  }, once = TRUE)

  # Poll build process --------
  observe({
    req(rv$building, !is.null(rv$build_proc))
    invalidateLater(500, session)

    latest_log <- read_build_log()
    if (length(latest_log)) rv$log_lines <- latest_log

    if (!rv$build_proc$is_alive()) {
      exit_code <- rv$build_proc$get_exit_status()
      if (is.null(exit_code)) exit_code <- 1L
      finalize_build(exit_code)
    }
  })

  # Status bar --------
  output$status_bar <- renderUI({
    fdir <- rv$framework_dir
    has_framework <- !is.null(fdir) && dir.exists(fdir)
    has_r <- has_framework && (
      dir.exists(file.path(fdir, "R-portable-master")) ||
        dir.exists(file.path(fdir, "R-portable"))
    )
    has_build <- has_framework && file.exists(file.path(fdir, "build", "build_packages.R"))

    div(class = "status-bar",
        div(class = "status-item",
            span(class = paste("dot", if (has_framework) "dot-ok" else "dot-err")),
            paste("Framework:", if (has_framework) basename(fdir) else "not found")
        ),
        div(class = "status-item",
            span(class = paste("dot", if (has_r) "dot-ok" else "dot-warn")),
            paste("Portable R:", if (has_r) "found" else "missing")
        ),
        div(class = "status-item",
            span(class = paste("dot", if (has_build) "dot-ok" else "dot-err")),
            paste("Build script:", if (has_build) "found" else "missing")
        )
    )
  })

  # Build overlay --------
  output$build_overlay <- renderUI({
    if (!rv$building) return(NULL)

    prog    <- parse_build_progress(rv$log_lines)
    pct     <- prog$pct %||% 0L
    phase   <- prog$phase %||% "init"
    label   <- prog$label %||% "Building..."
    detail  <- prog$detail %||% ""

    elapsed <- ""
    if (!is.null(rv$build_start_time)) {
      secs <- as.integer(difftime(Sys.time(), rv$build_start_time, units = "secs"))
      elapsed <- if (secs < 60) sprintf("%ds", secs) else sprintf("%dm %ds", secs %/% 60L, secs %% 60L)
    }

    fill_cls <- paste("progress-bar-fill", paste0("phase-", phase))

    div(class = "build-overlay",
        div(class = "overlay-card",
            div(class = "overlay-pct", pct, tags$span("%")),
            div(class = "progress-bar-track",
                div(class = fill_cls, style = sprintf("width: %d%%", max(pct, 2L)))
            ),
            div(class = "overlay-step", label),
            if (nzchar(detail)) div(class = "overlay-detail", detail),
            if (nzchar(elapsed)) div(class = "overlay-elapsed", paste("Elapsed:", elapsed))
        )
    )
  })

  # Clear button --------
  output$clear_button_ui <- renderUI({
    if (!rv$build_done) return(NULL)
    actionButton("clear_all", "New build", class = "btn-clear")
  })

  observeEvent(input$clear_all, {
    if (!is.null(rv$build_proc) && rv$build_proc$is_alive()) {
      try(rv$build_proc$kill(), silent = TRUE)
    }

    updateTextInput(session, "source_dir", value = "")
    updateTextInput(session, "app_name", value = "")
    updateTextInput(session, "output_dir", value = "")
    updateTextAreaInput(session, "extra_packages", value = "")
    updateCheckboxInput(session, "zip_output", value = TRUE)
    updateCheckboxInput(session, "build_offline_repo", value = FALSE)

    # Reset advanced controls if they exist
    try(updateCheckboxInput(session, "enable_write_mode", value = FALSE), silent = TRUE)
    try(updateCheckboxInput(session, "include_pandoc", value = FALSE), silent = TRUE)
    try(updateCheckboxInput(session, "bundle_rmarkdown_support", value = TRUE), silent = TRUE)
    if (!is.null(input$app_storage_dirs)) {
      try(updateCheckboxGroupInput(session, "app_storage_dirs", selected = character(0)), silent = TRUE)
    }

    rv$detected_pkgs <- character(0)
    rv$building <- FALSE
    rv$build_done <- FALSE
    rv$build_success <- FALSE
    rv$build_error <- NULL
    rv$log_lines <- character(0)
    rv$output_path <- NULL
    rv$zip_path <- NULL
    rv$build_proc <- NULL
    rv$health_check_results <- NULL
    rv$source_valid <- FALSE
    rv$source_validation_msg <- ""
    rv$build_start_time <- NULL

    cleanup_temp_files()
  })

  # Folder browsing --------
  observeEvent(input$browse_source, {
    dir <- tryCatch(utils::choose.dir(caption = "Select Shiny app folder"), error = function(e) NA)
    if (!is.na(dir) && nzchar(dir)) {
      updateTextInput(session, "source_dir", value = normalizePath(dir, winslash = "/"))
      if (!nzchar(input$app_name)) {
        updateTextInput(session, "app_name", value = basename(dir))
      }
    }
  })

  observeEvent(input$browse_output, {
    dir <- tryCatch(utils::choose.dir(caption = "Select output folder"), error = function(e) NA)
    if (!is.na(dir) && nzchar(dir)) {
      updateTextInput(session, "output_dir", value = normalizePath(dir, winslash = "/"))
    }
  })

  # Auto-fill output dir --------
  observeEvent(input$app_name, {
    if (nzchar(input$app_name) && !nzchar(input$output_dir)) {
      safe_name <- gsub("[^A-Za-z0-9_]+", "_", input$app_name)
      safe_name <- gsub("_+", "_", safe_name)
      safe_name <- gsub("^_|_$", "", safe_name)
      parent <- dirname(rv$framework_dir %||% ".")
      default_out <- file.path(parent, paste0(safe_name, "_deploy"))
      updateTextInput(session, "output_dir",
                      value = normalizePath(default_out, winslash = "/", mustWork = FALSE))
    }
  })

  # Detect dependencies + validate source structure --------
  observeEvent(input$source_dir, {
    src <- trimws(input$source_dir %||% "")
    if (!nzchar(src) || !dir.exists(src)) {
      rv$detected_pkgs <- character(0)
      rv$source_valid <- FALSE
      rv$source_validation_msg <- ""
      return()
    }
    env <- rv$publisher_env
    if (is.null(env)) return()

    # Structure validation
    tryCatch({
      mode <- env$detect_app_mode(normalizePath(src, winslash = "/", mustWork = TRUE))
      rv$source_valid <- TRUE
      rv$source_validation_msg <- switch(mode,
        "app.R"     = "app.R found",
        "ui_server" = "ui.R + server.R found",
        paste("Valid:", mode)
      )
    }, error = function(e) {
      rv$source_valid <- FALSE
      rv$source_validation_msg <- conditionMessage(e)
    })

    # Dependency detection (only if valid)
    if (rv$source_valid) {
      tryCatch({
        pkgs <- env$detect_dependencies(normalizePath(src, winslash = "/", mustWork = TRUE))
        pkgs <- unique(c("shiny", pkgs))
        rv$detected_pkgs <- sort(pkgs)
      }, error = function(e) {
        rv$detected_pkgs <- "shiny"
      })
    } else {
      rv$detected_pkgs <- character(0)
    }
  }, ignoreInit = FALSE)

  output$source_validation_ui <- renderUI({
    src <- trimws(input$source_dir %||% "")
    if (!nzchar(src)) return(NULL)
    if (!dir.exists(src)) {
      return(span(class = "validation-badge validation-err", "Folder not found"))
    }
    if (rv$source_valid) {
      span(class = "validation-badge validation-ok", rv$source_validation_msg)
    } else {
      span(class = "validation-badge validation-err", rv$source_validation_msg)
    }
  })

  output$detected_packages <- renderUI({
    pkgs <- rv$detected_pkgs
    if (!length(pkgs)) {
      return(div(class = "pkg-list", style = "color: #9ca3af;",
                 "Select a source folder to scan for packages"))
    }
    tagList(
      div(class = "pkg-list", paste(pkgs, collapse = ", ")),
      div(class = "pkg-count", paste(length(pkgs), "packages detected from code"))
    )
  })

  # Advanced features UI --------
  output$writable_dirs_ui <- renderUI({
    req(input$enable_write_mode)
    dirs <- app_subdirs()
    selected_defaults <- intersect(c("data", "uploads", "logs", "tmp", "cache"), dirs)

    if (!length(dirs)) {
      return(div(class = "folder-picker-empty",
                 "No app subfolders found. Select a valid app folder first."))
    }

    div(class = "folder-picker",
        checkboxGroupInput("app_storage_dirs", "Writable folders to include",
                           choices = dirs, selected = selected_defaults)
    )
  })

  # Build button --------
  can_build <- reactive({
    !rv$building &&
      nzchar(input$source_dir %||% "") &&
      dir.exists(input$source_dir %||% "") &&
      isTRUE(rv$source_valid) &&
      nzchar(input$app_name %||% "") &&
      nzchar(input$output_dir %||% "") &&
      !is.null(rv$build_rscript_path)
  })

  output$build_button_ui <- renderUI({
    if (rv$building) {
      actionButton("build_app", "Building...", class = "btn-build", disabled = "")
    } else {
      actionButton("build_app", "Build deployment", class = "btn-build",
                   disabled = if (!can_build()) "" else NULL)
    }
  })


  # Build via background subprocess --------
  observeEvent(input$build_app, {
    req(can_build())

    if (!requireNamespace("processx", quietly = TRUE)) {
      rv$building <- FALSE
      rv$build_done <- TRUE
      rv$build_success <- FALSE
      rv$build_error <- "The processx package is required. Please install processx."
      rv$log_lines <- c("[ERROR] processx is not installed.")
      return()
    }

    rv$building <- TRUE
    rv$build_done <- FALSE
    rv$build_success <- FALSE
    rv$build_error <- NULL
    rv$log_lines <- character(0)
    rv$output_path <- NULL
    rv$zip_path <- NULL
    rv$build_start_time <- Sys.time()

    cleanup_temp_files()

    # Extra packages from textarea --------
    extra_pkgs <- trimws(unlist(strsplit(input$extra_packages %||% "", "\n", fixed = TRUE)))
    extra_pkgs <- unique(extra_pkgs[nzchar(extra_pkgs)])
    if (length(extra_pkgs)) {
      rv$req_extra_file <- tempfile("req_extra_", fileext = ".txt")
      writeLines(extra_pkgs, rv$req_extra_file)
    }

    # Advanced features JSON handoff --------
    selected_writable_dirs <- if (is.null(input$app_storage_dirs)) character(0) else input$app_storage_dirs
    app_features <- list(
      enable_write_mode = isTRUE(input$enable_write_mode),
      writable_dirs = unname(selected_writable_dirs),
      include_pandoc = isTRUE(input$include_pandoc),
      bundle_rmarkdown_support = isTRUE(input$bundle_rmarkdown_support)
    )
    rv$app_features_file <- tempfile("app_features_", fileext = ".json")
    jsonlite::write_json(app_features, path = rv$app_features_file, auto_unbox = TRUE, pretty = TRUE)

    # Log file setup --------
    cleanup_old_publisher_logs(30)
    rv$build_log_file <- new_publisher_log_file()
    writeLines(character(0), rv$build_log_file, useBytes = TRUE)

    # Resolve paths --------
    publish_script <- normalizePath(
      file.path(rv$framework_dir, "build", "publish_app.R"),
      winslash = "/", mustWork = TRUE)
    source_dir <- normalizePath(input$source_dir, winslash = "/", mustWork = TRUE)
    output_dir <- normalizePath(input$output_dir, winslash = "/", mustWork = FALSE)
    rscript <- rv$build_rscript_path
    framework_dir <- normalizePath(rv$framework_dir, winslash = "/", mustWork = TRUE)

    portable_rscript_candidates <- normalizePath(
      c(
        file.path(framework_dir, "R-portable", "bin", "Rscript.exe"),
        file.path(framework_dir, "R-portable", "bin", "x64", "Rscript.exe"),
        file.path(framework_dir, "R-portable-master", "bin", "Rscript.exe"),
        file.path(framework_dir, "R-portable-master", "bin", "x64", "Rscript.exe")
      ),
      winslash = "/",
      mustWork = FALSE
    )

    if (normalizePath(rscript, winslash = "/", mustWork = FALSE) %in% portable_rscript_candidates) {
      stop(
        "Build cannot run using framework_dir/R-portable or framework_dir/R-portable-master Rscript.exe because that same portable R is being copied into the deployment."
      )
    }

    # CLI arguments --------
    cli_args <- c(
      "--vanilla",
      publish_script,
      "--framework_dir", framework_dir,
      "--source", source_dir,
      "--output", output_dir,
      "--app_name", input$app_name,
      "--app_features_file", rv$app_features_file
    )

    if (!is.null(rv$req_extra_file) && file.exists(rv$req_extra_file)) {
      cli_args <- c(cli_args, "--req_extra_file", rv$req_extra_file)
    }
    if (isTRUE(input$zip_output)) {
      cli_args <- c(cli_args, "--zip")
    }
    if (isTRUE(input$build_offline_repo)) {
      cli_args <- c(cli_args, "--build_offline_repo")
    }
    data_dir_val <- trimws(input$data_dir %||% "")
    if (nzchar(data_dir_val)) {
      cli_args <- c(cli_args, "--data_dir", data_dir_val)
    }

    # Write startup log --------
    rv$log_lines <- c(
      paste("[ui] rscript =", rscript),
      paste("[ui] publish_script =", publish_script),
      paste("[ui] framework_dir =", framework_dir),
      paste("[ui] source_dir =", source_dir),
      paste("[ui] output_dir =", output_dir),
      paste("[ui] app_name =", input$app_name),
      paste("[ui] build_log_file =", rv$build_log_file),
      paste("[ui] enable_write_mode =", isTRUE(input$enable_write_mode)),
      paste("[ui] app_storage_dirs =", paste(selected_writable_dirs, collapse = ", ")),
      paste("[ui] include_pandoc =", isTRUE(input$include_pandoc)),
      paste("[ui] bundle_rmarkdown_support =", isTRUE(input$bundle_rmarkdown_support)),
      paste("[ui] app_features_file =", rv$app_features_file),
      paste("[ui] data_dir =", trimws(input$data_dir %||% "")),
      "[ui] Starting background build process..."
    )
    writeLines(rv$log_lines, rv$build_log_file, useBytes = TRUE)

    # Launch hidden subprocess --------
    tryCatch({
      bat_quote <- function(x) {
        if (startsWith(x, "--")) return(x)
        paste0('"', x, '"')
      }

      cmd_parts <- c(
        paste0('"', rscript, '"'),
        vapply(cli_args, bat_quote, character(1), USE.NAMES = FALSE)
      )
      full_cmd <- paste(cmd_parts, collapse = " ")

      temp_bat <- tempfile("sb_build_", fileext = ".bat")
      bat_lines <- c("@echo off", paste0(full_cmd, ' >> "', rv$build_log_file, '" 2>&1'))
      writeLines(bat_lines, temp_bat, useBytes = TRUE)
      rv$temp_bat_file <- temp_bat

      vbs_path <- normalizePath(
        file.path(rv$framework_dir, "build", "run_hidden.vbs"),
        winslash = "/", mustWork = TRUE)

      rv$build_proc <- processx::process$new(
        command = "wscript.exe",
        args = c("//nologo", "//B", vbs_path, temp_bat),
        stdout = "|", stderr = "|",
        windows_hide_window = TRUE, cleanup = FALSE)

    }, error = function(e) {
      rv$building <- FALSE
      rv$build_done <- TRUE
      rv$build_success <- FALSE
      rv$build_error <- conditionMessage(e)
      append_log_lines(paste("[ERROR]", conditionMessage(e)))
      cleanup_temp_files()
      rv$build_proc <- NULL
    })
  })

  # Strip R — browse --------
  observeEvent(input$browse_r_source, {
    dir <- tryCatch(utils::choose.dir(caption = "Select full R installation folder"), error = function(e) NA)
    if (!is.na(dir) && nzchar(dir)) {
      updateTextInput(session, "r_source_dir", value = normalizePath(dir, winslash = "/"))
    }
  })

  # Strip R — button UI --------
  output$strip_r_button_ui <- renderUI({
    label <- if (rv$strip_r_running) "Creating R-portable..." else "Create portable R"
    actionButton("build_portable_r", label, class = "btn-secondary",
                 disabled = if (!can_strip_r()) "" else NULL)
  })

  # Strip R — result display --------
  output$strip_r_result <- renderUI({
    if (!rv$strip_r_done) {
      status_text <- if (portable_r_exists()) {
        "Portable R is available in the framework."
      } else {
        "Portable R is not yet available."
      }
      return(div(class = "log-meta", status_text))
    }

    if (rv$strip_r_success) {
      div(class = "result-bar success",
          div(class = "result-info",
              strong("Portable R created successfully."), br(),
              paste("Master:", file.path(rv$framework_dir, "R-portable-master")), br(),
              paste("Runtime:", file.path(rv$framework_dir, "R-portable"))
          )
      )
    } else {
      div(class = "result-bar error",
          div(class = "result-info",
              strong("Portable R creation failed."), br(),
              rv$strip_r_error
          )
      )
    }
  })

  # Strip R — log viewer --------
  output$strip_r_log_section <- renderUI({
    if (!length(rv$strip_r_log_lines)) return(NULL)

    colored <- lapply(rv$strip_r_log_lines, function(l) {
      cls <- if (grepl("Error|FAIL|WARNING|cannot|failed", l, ignore.case = TRUE)) "log-error"
      else if (grepl("PASSED|Verification|SUMMARY|Output|Verified", l, ignore.case = TRUE)) "log-ok"
      else NULL
      if (!is.null(cls)) tags$span(class = cls, paste0(l, "\n")) else paste0(l, "\n")
    })

    div(style = "margin-top: 14px;",
        h3("Portable R setup log"),
        div(class = "log-output", do.call(tagList, colored))
    )
  })

  # Strip R — launch background process --------
  observeEvent(input$build_portable_r, {
    req(can_strip_r())

    if (!requireNamespace("processx", quietly = TRUE)) {
      rv$strip_r_running <- FALSE
      rv$strip_r_done <- TRUE
      rv$strip_r_success <- FALSE
      rv$strip_r_error <- "The processx package is required. Please install processx."
      rv$strip_r_log_lines <- c("[ERROR] processx is not installed.")
      return()
    }

    rv$strip_r_running <- TRUE
    rv$strip_r_done <- FALSE
    rv$strip_r_success <- FALSE
    rv$strip_r_error <- NULL
    rv$strip_r_log_lines <- character(0)

    rv$strip_r_log_file <- new_publisher_log_file(prefix = "strip_r")
    writeLines(character(0), rv$strip_r_log_file, useBytes = TRUE)

    strip_script <- normalizePath(
      file.path(rv$framework_dir, "strip_r.R"),
      winslash = "/", mustWork = TRUE)
    r_source_dir <- normalizePath(input$r_source_dir, winslash = "/", mustWork = TRUE)
    framework_dir <- normalizePath(rv$framework_dir, winslash = "/", mustWork = TRUE)
    rscript <- rv$build_rscript_path

    cli_args <- c("--vanilla", strip_script,
                  "--r_source", r_source_dir,
                  "--framework_dir", framework_dir)

    if (isTRUE(input$keep_tcltk)) cli_args <- c(cli_args, "--keep_tcltk")
    if (isTRUE(input$strip_pkg_docs)) cli_args <- c(cli_args, "--strip_pkg_docs")

    rv$strip_r_log_lines <- c(
      paste("[ui] rscript =", rscript),
      paste("[ui] strip_script =", strip_script),
      paste("[ui] framework_dir =", framework_dir),
      paste("[ui] r_source_dir =", r_source_dir),
      paste("[ui] strip_r_log_file =", rv$strip_r_log_file),
      "[ui] Starting portable R creation..."
    )
    writeLines(rv$strip_r_log_lines, rv$strip_r_log_file, useBytes = TRUE)

    tryCatch({
      bat_quote <- function(x) {
        if (startsWith(x, "--")) return(x)
        paste0('"', x, '"')
      }

      cmd_parts <- c(
        paste0('"', rscript, '"'),
        vapply(cli_args, bat_quote, character(1), USE.NAMES = FALSE)
      )
      full_cmd <- paste(cmd_parts, collapse = " ")

      temp_bat <- tempfile("sb_strip_r_", fileext = ".bat")
      bat_lines <- c("@echo off", paste0(full_cmd, ' >> "', rv$strip_r_log_file, '" 2>&1'))
      writeLines(bat_lines, temp_bat, useBytes = TRUE)
      rv$strip_r_bat_file <- temp_bat

      vbs_path <- normalizePath(
        file.path(rv$framework_dir, "build", "run_hidden.vbs"),
        winslash = "/", mustWork = TRUE)

      rv$strip_r_proc <- processx::process$new(
        command = "wscript.exe",
        args = c("//nologo", "//B", vbs_path, temp_bat),
        stdout = "|", stderr = "|",
        windows_hide_window = TRUE, cleanup = FALSE)

    }, error = function(e) {
      rv$strip_r_running <- FALSE
      rv$strip_r_done <- TRUE
      rv$strip_r_success <- FALSE
      rv$strip_r_error <- conditionMessage(e)
      rv$strip_r_log_lines <- c(rv$strip_r_log_lines, paste("[ERROR]", conditionMessage(e)))
      rv$strip_r_proc <- NULL
    })
  })

  # Strip R — poll process --------
  observe({
    req(rv$strip_r_running, !is.null(rv$strip_r_proc))
    invalidateLater(500, session)

    latest_log <- read_strip_r_log()
    if (length(latest_log)) rv$strip_r_log_lines <- latest_log

    if (!rv$strip_r_proc$is_alive()) {
      exit_code <- rv$strip_r_proc$get_exit_status()
      if (is.null(exit_code)) exit_code <- 1L

      latest_log <- read_strip_r_log()
      if (length(latest_log)) rv$strip_r_log_lines <- latest_log

      rv$strip_r_running <- FALSE
      rv$strip_r_done <- TRUE
      rv$strip_r_success <- identical(as.integer(exit_code), 0L)

      if (rv$strip_r_success) {
        rv$strip_r_error <- NULL
        rv$rscript_path <- find_rscript(rv$framework_dir)
        rv$build_rscript_path <- find_build_rscript(rv$framework_dir)
      } else {
        error_lines <- grep("Error|error|FAIL|cannot|failed|WARNING",
                            rv$strip_r_log_lines, value = TRUE, ignore.case = TRUE)
        rv$strip_r_error <- if (length(error_lines)) {
          paste(tail(error_lines, 5), collapse = "\n")
        } else {
          paste("Portable R creation exited with code", exit_code)
        }
      }

      # Clean up temp bat
      if (!is.null(rv$strip_r_bat_file) && file.exists(rv$strip_r_bat_file)) {
        try(unlink(rv$strip_r_bat_file), silent = TRUE)
      }
      rv$strip_r_bat_file <- NULL
      rv$strip_r_proc <- NULL

      refresh_log_choices(select_latest = TRUE)
    }
  })

  # Build log section --------
  output$log_section <- renderUI({
    if (!length(rv$log_lines)) return(NULL)

    colored <- lapply(rv$log_lines, function(l) {
      cls <- if (grepl("Error|FAIL|missing after|cannot|failed", l, ignore.case = TRUE)) "log-error"
      else if (grepl("Done|OK|PASSED|written|Copying|detected|successful", l, ignore.case = TRUE)) "log-ok"
      else NULL
      if (!is.null(cls)) tags$span(class = cls, paste0(l, "\n")) else paste0(l, "\n")
    })

    div(class = "card",
        h3("Current build log"),
        div(class = "log-output", do.call(tagList, colored))
    )
  })

  # Publisher log viewer --------
  observeEvent(rv$framework_dir, {
    req(!is.null(rv$framework_dir))
    refresh_log_choices(select_latest = TRUE)
  }, ignoreInit = FALSE)

  observeEvent(input$refresh_logs, {
    refresh_log_choices(select_latest = TRUE)
  })

  observeEvent(input$view_log, {
    path <- input$selected_log_file %||% ""
    if (!nzchar(path) || !file.exists(path)) {
      rv$selected_log_path <- NULL
      rv$selected_log_lines <- character(0)
      return()
    }
    rv$selected_log_path <- path
    rv$selected_log_lines <- read_selected_log(path, tail_lines = 250)
  })

  observeEvent(input$selected_log_file, {
    path <- input$selected_log_file %||% ""
    if (!nzchar(path) || !file.exists(path)) {
      rv$selected_log_path <- NULL
      rv$selected_log_lines <- character(0)
      return()
    }
    rv$selected_log_path <- path
    rv$selected_log_lines <- read_selected_log(path, tail_lines = 250)
  }, ignoreInit = TRUE)

  # Delete selected log --------
  observeEvent(input$delete_log, {
    path <- input$selected_log_file %||% ""
    if (!nzchar(path) || !file.exists(path)) return()

    try(unlink(path, force = TRUE), silent = TRUE)
    if (identical(rv$selected_log_path, path)) {
      rv$selected_log_path <- NULL
      rv$selected_log_lines <- character(0)
    }
    refresh_log_choices(select_latest = TRUE)
  })

  # Delete all logs --------
  observeEvent(input$delete_all_logs, {
    files <- list_publisher_logs()
    if (!length(files)) return()

    try(unlink(files, force = TRUE), silent = TRUE)
    rv$selected_log_path <- NULL
    rv$selected_log_lines <- character(0)
    refresh_log_choices(select_latest = FALSE)
  })

  # Log metadata display --------
  output$selected_log_meta <- renderUI({
    path <- rv$selected_log_path
    if (is.null(path) || !nzchar(path) || !file.exists(path)) {
      return(div(class = "log-meta", "No log selected"))
    }
    info <- file.info(path)
    div(class = "log-meta",
        paste0("File: ", basename(path),
               " | Modified: ", format(info$mtime, "%Y-%m-%d %H:%M:%S"),
               " | Size: ", format(round(info$size / 1024, 1), nsmall = 1), " KB"))
  })

  # Log preview --------
  output$selected_log_preview <- renderUI({
    lines <- rv$selected_log_lines
    if (!length(lines)) {
      return(div(class = "log-preview", style = "color: #9ca3af;",
                 "Select a log file to preview the last 250 lines"))
    }

    colored <- lapply(lines, function(l) {
      cls <- if (grepl("Error|FAIL|missing after|cannot|failed|Execution halted", l, ignore.case = TRUE)) "log-error"
      else if (grepl("Done|OK|PASSED|written|Copying|detected|successful", l, ignore.case = TRUE)) "log-ok"
      else NULL
      if (!is.null(cls)) tags$span(class = cls, paste0(l, "\n")) else paste0(l, "\n")
    })

    div(class = "log-preview", do.call(tagList, colored))
  })

  # Build result bar --------
  output$build_result <- renderUI({
    if (!rv$build_done) return(NULL)

    if (rv$build_success) {
      div(class = "result-bar success",
          div(class = "result-info",
              strong("Build successful."), br(),
              paste("Output:", rv$output_path),
              if (!is.null(rv$zip_path)) tagList(br(), paste("Zip:", rv$zip_path))
          ),
          tagList(
            if (!is.null(rv$zip_path) && file.exists(rv$zip_path)) {
              downloadButton("download_zip", "Download zip",
                             style = "background:#16a34a;color:white;border:none;border-radius:6px;padding:8px 16px;font-size:13px;margin-right:6px;")
            },
            actionButton("test_launch", "Test launch", class = "btn-test-launch")
          )
      )
    } else {
      div(class = "result-bar error",
          div(class = "result-info",
              strong("Build failed."), br(),
              rv$build_error
          )
      )
    }
  })

  # Download handler --------
  output$download_zip <- downloadHandler(
    filename = function() basename(rv$zip_path %||% "deployment.zip"),
    content = function(file) file.copy(rv$zip_path, file),
    contentType = "application/zip"
  )
}


shinyApp(ui, server)
