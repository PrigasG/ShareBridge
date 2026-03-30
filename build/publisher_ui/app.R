# build/publisher_ui/app.R
# ------------------------------------------------------------------
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
# ------------------------------------------------------------------

library(shiny)

# ------------------------------------------------------------------
# Resolve framework directory
# ------------------------------------------------------------------
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

# ------------------------------------------------------------------
# Source publish_app.R for detect_dependencies only
# ------------------------------------------------------------------
load_publisher <- function(framework_dir) {
  publish_script <- file.path(framework_dir, "build", "publish_app.R")
  if (!file.exists(publish_script)) stop("publish_app.R not found at: ", publish_script)
  env <- new.env(parent = globalenv())
  sys.source(publish_script, envir = env)
  env
}

# ------------------------------------------------------------------
# Find Rscript executable
# ------------------------------------------------------------------
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

# ------------------------------------------------------------------
# UI
# ------------------------------------------------------------------
ui <- fluidPage(
  tags$head(
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
        background: rgba(255,255,255,0.88);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        z-index: 9999;
      }
      .spinner {
        width: 40px;
        height: 40px;
        border: 3px solid #e5e7eb;
        border-top-color: #2563eb;
        border-radius: 50%;
        animation: spin 0.8s linear infinite;
        margin-bottom: 16px;
      }
      @keyframes spin { to { transform: rotate(360deg); } }
      .overlay-text {
        font-size: 15px;
        font-weight: 500;
        color: #374151;
      }
      .overlay-sub {
        font-size: 13px;
        color: #6b7280;
        margin-top: 4px;
      }
      .toolbar-row {
        display: flex;
        gap: 8px;
        align-items: center;
        flex-wrap: wrap;
        margin-top: 8px;
      }
    "))
  ),

  div(class = "header",
      div(
        h2("ShareBridge Publisher"),
        p("Build portable Shiny app deployments")
      ),
      uiOutput("clear_button_ui")
  ),

  uiOutput("build_overlay"),
  uiOutput("status_bar"),

  div(class = "card",
      h3("Source app"),
      div(class = "form-group",
          tags$label("App folder"),
          div(class = "path-row",
              textInput("source_dir", label = NULL, value = "", width = "100%",
                        placeholder = "C:\\Users\\you\\projects\\my_shiny_app"),
              actionButton("browse_source", "Browse", class = "btn-browse")
          ),
          div(class = "help-text", "Folder containing app.R or ui.R + server.R")
      ),
      div(class = "form-group",
          textInput("app_name", "App name", value = "", placeholder = "My Dashboard"),
          div(class = "help-text", "Used for display name, port derivation, and folder naming")
      )
  ),

  div(class = "card",
      h3("Detected packages"),
      uiOutput("detected_packages"),
      div(class = "form-group", style = "margin-top: 14px;",
          textAreaInput("extra_packages", "Additional packages (one per line, optional)",
                        value = "", rows = 3, resize = "vertical",
                        placeholder = "arrow\njanitor"),
          div(class = "help-text", "Add packages that the scanner might miss (dynamic loading, etc.)")
      )
  ),

  div(class = "card",
      h3("Output"),
      div(class = "form-group",
          tags$label("Output folder"),
          div(class = "path-row",
              textInput("output_dir", label = NULL, value = "", width = "100%",
                        placeholder = "C:\\Users\\you\\Documents\\MyApp_deploy"),
              actionButton("browse_output", "Browse", class = "btn-browse")
          )
      ),
      div(style = "display: flex; gap: 24px; margin-top: 6px;",
          checkboxInput("zip_output", "Create zip file", value = TRUE),
          checkboxInput("build_offline_repo", "Build offline repo", value = FALSE)
      )
  ),

  div(class = "card",
      h3("Publisher logs"),
      div(class = "form-group",
          selectInput("selected_log_file", "Available log files", choices = character(0), width = "100%"),
          div(class = "help-text", "View or delete stored publisher log files")
      ),
      div(class = "toolbar-row",
          actionButton("refresh_logs", "Refresh list", class = "btn-log"),
          actionButton("view_log", "View selected log", class = "btn-log"),
          actionButton("delete_log", "Delete selected log", class = "btn-log-danger"),
          actionButton("delete_all_logs", "Delete all logs", class = "btn-log-danger")
      ),
      uiOutput("selected_log_meta"),
      uiOutput("selected_log_preview")
  ),

  div(style = "margin: 20px 0;", uiOutput("build_button_ui")),
  uiOutput("log_section"),
  uiOutput("build_result")
)

# ------------------------------------------------------------------
# Server
# ------------------------------------------------------------------
server <- function(input, output, session) {



  rv <- reactiveValues(
    framework_dir = NULL,
    publisher_env = NULL,
    rscript_path = NULL,
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
    req_extra_file = NULL,
    selected_log_lines = character(0),
    selected_log_path = NULL,
    temp_bat_file = NULL
  )

  session$onSessionEnded(function() {
    if (!is.null(rv$build_proc)) {
      try(rv$build_proc$kill(), silent = TRUE)
    }
    if (!is.null(rv$req_extra_file) && file.exists(rv$req_extra_file)) {
      try(unlink(rv$req_extra_file), silent = TRUE)
    }
    stopApp()
  })

  publisher_log_dir <- function() {
    req(rv$framework_dir)
    dir <- file.path(rv$framework_dir, "logs", "publisher")
    if (!dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    normalizePath(dir, winslash = "/", mustWork = TRUE)
  }

  new_publisher_log_file <- function() {
    log_dir <- publisher_log_dir()
    stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    file.path(log_dir, paste0("publish_", stamp, ".log"))
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

    if (length(old_files)) {
      unlink(old_files, force = TRUE)
    }

    invisible(NULL)
  }


  list_publisher_logs <- function() {
    if (is.null(rv$framework_dir) || !dir.exists(rv$framework_dir)) return(character(0))
    log_dir <- file.path(rv$framework_dir, "logs", "publisher")
    if (!dir.exists(log_dir)) return(character(0))

    files <- list.files(log_dir, pattern = "\\.log$", full.names = TRUE)
    if (!length(files)) return(character(0))

    info <- file.info(files)
    files <- files[order(info$mtime, decreasing = TRUE)]
    files
  }


  log_choices_named <- function() {
    files <- list_publisher_logs()
    if (!length(files)) return(setNames(character(0), character(0)))

    info <- file.info(files)
    labels <- paste0(
      basename(files),
      "  |  ",
      format(info$mtime, "%Y-%m-%d %H:%M"),
      "  |  ",
      format(round(info$size / 1024, 1), nsmall = 1),
      " KB"
    )
    stats::setNames(files, labels)
  }

  refresh_log_choices <- function(select_latest = TRUE) {
    choices <- log_choices_named()

    updateSelectInput(
      session,
      "selected_log_file",
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
    if (length(lines) > tail_lines) {
      lines <- tail(lines, tail_lines)
    }
    lines
  }

  # ---------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------
  append_log_lines <- function(lines) {
    lines <- as.character(lines)
    lines <- lines[nzchar(lines)]
    if (!length(lines)) return(invisible(NULL))
    rv$log_lines <- c(rv$log_lines, lines)
    invisible(NULL)
  }

  read_build_log <- function() {
    if (is.null(rv$build_log_file) || !file.exists(rv$build_log_file)) {
      return(character(0))
    }
    tryCatch(readLines(rv$build_log_file, warn = FALSE), error = function(e) character(0))
  }

  cleanup_temp_files <- function() {
    if (!is.null(rv$req_extra_file) && file.exists(rv$req_extra_file)) {
      try(unlink(rv$req_extra_file), silent = TRUE)
    }
    rv$req_extra_file <- NULL
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
    if (length(latest_log)) {
      rv$log_lines <- latest_log
    }

    if (rv$build_success) {
      rv$output_path <- normalizePath(input$output_dir, winslash = "/", mustWork = FALSE)
      zip_candidate <- paste0(rv$output_path, ".zip")
      if (file.exists(zip_candidate)) {
        rv$zip_path <- zip_candidate
      } else {
        rv$zip_path <- NULL
      }
      rv$build_error <- NULL
    } else {
      error_lines <- grep(
        "Error|error|FAIL|stop|missing|cannot|failed",
        rv$log_lines,
        value = TRUE,
        ignore.case = TRUE
      )
      rv$build_error <- if (length(error_lines)) {
        paste(tail(error_lines, 5), collapse = "\n")
      } else {
        paste("Build exited with code", exit_code)
      }
    }

    cleanup_temp_files()

    if (!is.null(rv$build_proc)) {
      try(rv$build_proc$kill(), silent = TRUE)
    }
    rv$build_proc <- NULL
    refresh_log_choices(select_latest = TRUE)
  }



  # ---------------------------------------------------------
  # Initialize once
  # ---------------------------------------------------------
  observeEvent(TRUE, {
    tryCatch({
      rv$framework_dir <- resolve_framework_dir()
      rv$publisher_env <- load_publisher(rv$framework_dir)
      rv$rscript_path <- find_rscript(rv$framework_dir)
    }, error = function(e) {
      rv$framework_dir <- NULL
      rv$publisher_env <- NULL
      rv$rscript_path <- NULL
      rv$build_error <- conditionMessage(e)
    })
  }, once = TRUE)

  # ---------------------------------------------------------
  # Poll background build while active
  # ---------------------------------------------------------
  observe({
    req(rv$building)
    req(!is.null(rv$build_proc))

    invalidateLater(500, session)

    latest_log <- read_build_log()
    if (length(latest_log)) {
      rv$log_lines <- latest_log
    }

    if (!rv$build_proc$is_alive()) {
      exit_code <- rv$build_proc$get_exit_status()
      if (is.null(exit_code)) exit_code <- 1L
      finalize_build(exit_code)
    }
  })

  # ---------------------------------------------------------
  # Status bar
  # ---------------------------------------------------------
  output$status_bar <- renderUI({
    fdir <- rv$framework_dir
    has_framework <- !is.null(fdir) && dir.exists(fdir)
    has_r <- has_framework && dir.exists(file.path(fdir, "R-portable"))
    has_build <- has_framework && file.exists(file.path(fdir, "build", "build_packages.R"))

    div(
      class = "status-bar",
      div(
        class = "status-item",
        span(class = paste("dot", if (has_framework) "dot-ok" else "dot-err")),
        paste("Framework:", if (has_framework) basename(fdir) else "not found")
      ),
      div(
        class = "status-item",
        span(class = paste("dot", if (has_r) "dot-ok" else "dot-warn")),
        paste("Portable R:", if (has_r) "found" else "missing")
      ),
      div(
        class = "status-item",
        span(class = paste("dot", if (has_build) "dot-ok" else "dot-err")),
        paste("Build script:", if (has_build) "found" else "missing")
      )
    )
  })

  # ---------------------------------------------------------
  # Overlay
  # ---------------------------------------------------------
  output$build_overlay <- renderUI({
    if (!rv$building) return(NULL)
    div(
      class = "build-overlay",
      div(class = "spinner"),
      div(class = "overlay-text", "Building deployment..."),
      div(class = "overlay-sub", "Please wait. Inputs are temporarily locked until the build finishes.")
    )
  })

  # ---------------------------------------------------------
  # Clear button
  # ---------------------------------------------------------
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

    rv$detected_pkgs <- character(0)
    rv$building <- FALSE
    rv$build_done <- FALSE
    rv$build_success <- FALSE
    rv$build_error <- NULL
    rv$log_lines <- character(0)
    rv$output_path <- NULL
    rv$zip_path <- NULL
    rv$build_proc <- NULL

    cleanup_temp_files()
  })

  # ---------------------------------------------------------
  # Folder browsing
  # ---------------------------------------------------------
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

  # ---------------------------------------------------------
  # Auto-fill output dir
  # ---------------------------------------------------------
  observeEvent(input$app_name, {
    if (nzchar(input$app_name) && !nzchar(input$output_dir)) {
      safe_name <- gsub("[^A-Za-z0-9_]+", "_", input$app_name)
      safe_name <- gsub("_+", "_", safe_name)
      safe_name <- gsub("^_|_$", "", safe_name)
      parent <- dirname(rv$framework_dir %||% ".")
      default_out <- file.path(parent, paste0(safe_name, "_deploy"))
      updateTextInput(
        session,
        "output_dir",
        value = normalizePath(default_out, winslash = "/", mustWork = FALSE)
      )
    }
  })

  # ---------------------------------------------------------
  # Detect dependencies
  # ---------------------------------------------------------
  observeEvent(input$source_dir, {
    src <- trimws(input$source_dir %||% "")
    if (!nzchar(src) || !dir.exists(src)) {
      rv$detected_pkgs <- character(0)
      return()
    }

    env <- rv$publisher_env
    if (is.null(env)) return()

    tryCatch({
      pkgs <- env$detect_dependencies(normalizePath(src, winslash = "/", mustWork = TRUE))
      pkgs <- unique(c("shiny", pkgs))
      rv$detected_pkgs <- sort(pkgs)
    }, error = function(e) {
      rv$detected_pkgs <- "shiny"
    })
  }, ignoreInit = FALSE)

  output$detected_packages <- renderUI({
    pkgs <- rv$detected_pkgs
    if (!length(pkgs)) {
      return(
        div(
          class = "pkg-list",
          style = "color: #9ca3af;",
          "Select a source folder to scan for packages"
        )
      )
    }

    tagList(
      div(class = "pkg-list", paste(pkgs, collapse = ", ")),
      div(class = "pkg-count", paste(length(pkgs), "packages detected from code"))
    )
  })

  # ---------------------------------------------------------
  # Build button
  # ---------------------------------------------------------
  can_build <- reactive({
    !rv$building &&
      nzchar(input$source_dir %||% "") &&
      dir.exists(input$source_dir %||% "") &&
      nzchar(input$app_name %||% "") &&
      nzchar(input$output_dir %||% "") &&
      !is.null(rv$rscript_path)
  })

  output$build_button_ui <- renderUI({
    if (rv$building) {
      actionButton("build_app", "Building...", class = "btn-build", disabled = "")
    } else {
      actionButton(
        "build_app",
        "Build deployment",
        class = "btn-build",
        disabled = if (!can_build()) "" else NULL
      )
    }
  })

  # ---------------------------------------------------------
  # Build via background subprocess
  # ---------------------------------------------------------
  observeEvent(input$build_app, {
    req(can_build())

    if (!requireNamespace("processx", quietly = TRUE)) {
      rv$building <- FALSE
      rv$build_done <- TRUE
      rv$build_success <- FALSE
      rv$build_error <- "The processx package is required for background builds. Please install processx."
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

    cleanup_temp_files()

    extra_pkgs <- trimws(unlist(strsplit(input$extra_packages %||% "", "\n", fixed = TRUE)))
    extra_pkgs <- unique(extra_pkgs[nzchar(extra_pkgs)])

    if (length(extra_pkgs)) {
      rv$req_extra_file <- tempfile("req_extra_", fileext = ".txt")
      writeLines(extra_pkgs, rv$req_extra_file)
    }

    cleanup_old_publisher_logs(30)
    rv$build_log_file <- new_publisher_log_file()

    writeLines(character(0), rv$build_log_file, useBytes = TRUE)

    publish_script <- normalizePath(
      file.path(rv$framework_dir, "build", "publish_app.R"),
      winslash = "/",
      mustWork = TRUE
    )

    source_dir <- normalizePath(input$source_dir, winslash = "/", mustWork = TRUE)
    output_dir <- normalizePath(input$output_dir, winslash = "/", mustWork = FALSE)
    framework_dir <- normalizePath(rv$framework_dir, winslash = "/", mustWork = TRUE)
    rscript <- rv$rscript_path

    cli_args <- c(
      "--vanilla",
      publish_script,
      "--framework_dir", framework_dir,
      "--source", source_dir,
      "--output", output_dir,
      "--app_name", input$app_name
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

    rv$log_lines <- c(
      paste("[ui] rscript =", rscript),
      paste("[ui] publish_script =", publish_script),
      paste("[ui] framework_dir =", framework_dir),
      paste("[ui] source_dir =", source_dir),
      paste("[ui] output_dir =", output_dir),
      paste("[ui] app_name =", input$app_name),
      paste("[ui] build_log_file =", rv$build_log_file),
      "[ui] Starting background build process..."
    )
    writeLines(rv$log_lines, rv$build_log_file, useBytes = TRUE)

    tryCatch({
      # Quote each path argument for batch file context
      bat_quote <- function(x) {
        if (startsWith(x, "--")) return(x)
        paste0('"', x, '"')
      }

      cmd_parts <- c(
        paste0('"', rscript, '"'),
        vapply(cli_args, bat_quote, character(1), USE.NAMES = FALSE)
      )
      full_cmd <- paste(cmd_parts, collapse = " ")

      # Write temp .bat with command + log redirection
      temp_bat <- tempfile("sb_build_", fileext = ".bat")
      bat_lines <- c(
        "@echo off",
        paste0(full_cmd, ' >> "', rv$build_log_file, '" 2>&1')
      )
      writeLines(bat_lines, temp_bat, useBytes = TRUE)
      rv$temp_bat_file <- temp_bat

      # wscript.exe is a GUI app — no console window at all
      vbs_path <- normalizePath(
        file.path(rv$framework_dir, "build", "run_hidden.vbs"),
        winslash = "/",
        mustWork = TRUE
      )

      rv$build_proc <- processx::process$new(
        command = "wscript.exe",
        args = c("//nologo", "//B", vbs_path, temp_bat),
        stdout = "|",
        stderr = "|",
        windows_hide_window = TRUE,
        cleanup = FALSE
      )
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

  # ---------------------------------------------------------
  # Log section
  # ---------------------------------------------------------
  output$log_section <- renderUI({
    if (!length(rv$log_lines)) return(NULL)

    colored <- lapply(rv$log_lines, function(l) {
      cls <- if (grepl("Error|FAIL|missing after|cannot|failed", l, ignore.case = TRUE)) {
        "log-error"
      } else if (grepl("Done|OK|PASSED|written|Copying|detected|successful", l, ignore.case = TRUE)) {
        "log-ok"
      } else {
        NULL
      }

      if (!is.null(cls)) {
        tags$span(class = cls, paste0(l, "\n"))
      } else {
        paste0(l, "\n")
      }
    })

    div(
      class = "card",
      h3("Current build log"),
      div(class = "log-output", do.call(tagList, colored))
    )
  })


  # view log
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


  #delete selected logs
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


  #delete all logs
  observeEvent(input$delete_all_logs, {
    files <- list_publisher_logs()
    if (!length(files)) return()

    try(unlink(files, force = TRUE), silent = TRUE)

    rv$selected_log_path <- NULL
    rv$selected_log_lines <- character(0)

    refresh_log_choices(select_latest = FALSE)
  })


  #Render selected log metadata
  output$selected_log_meta <- renderUI({
    path <- rv$selected_log_path
    if (is.null(path) || !nzchar(path) || !file.exists(path)) {
      return(div(class = "log-meta", "No log selected"))
    }

    info <- file.info(path)
    div(
      class = "log-meta",
      paste0(
        "File: ", basename(path),
        " | Modified: ", format(info$mtime, "%Y-%m-%d %H:%M:%S"),
        " | Size: ", format(round(info$size / 1024, 1), nsmall = 1), " KB"
      )
    )
  })


  output$selected_log_preview <- renderUI({
    lines <- rv$selected_log_lines
    if (!length(lines)) {
      return(
        div(
          class = "log-preview",
          style = "color: #9ca3af;",
          "Select a log file to preview the last 250 lines"
        )
      )
    }

    colored <- lapply(lines, function(l) {
      cls <- if (grepl("Error|FAIL|missing after|cannot|failed|Execution halted", l, ignore.case = TRUE)) {
        "log-error"
      } else if (grepl("Done|OK|PASSED|written|Copying|detected|successful", l, ignore.case = TRUE)) {
        "log-ok"
      } else {
        NULL
      }

      if (!is.null(cls)) {
        tags$span(class = cls, paste0(l, "\n"))
      } else {
        paste0(l, "\n")
      }
    })

    div(class = "log-preview", do.call(tagList, colored))
  })




  # ---------------------------------------------------------
  # Result bar
  # ---------------------------------------------------------
  output$build_result <- renderUI({
    if (!rv$build_done) return(NULL)

    if (rv$build_success) {
      div(
        class = "result-bar success",
        div(
          class = "result-info",
          strong("Build successful."),
          br(),
          paste("Output:", rv$output_path),
          if (!is.null(rv$zip_path)) tagList(br(), paste("Zip:", rv$zip_path))
        ),
        if (!is.null(rv$zip_path) && file.exists(rv$zip_path)) {
          downloadButton(
            "download_zip",
            "Download zip",
            style = "background:#16a34a;color:white;border:none;border-radius:6px;padding:8px 16px;font-size:13px;"
          )
        }
      )
    } else {
      div(
        class = "result-bar error",
        div(
          class = "result-info",
          strong("Build failed."),
          br(),
          rv$build_error
        )
      )
    }
  })

  # ---------------------------------------------------------
  # Download
  # ---------------------------------------------------------
  output$download_zip <- downloadHandler(
    filename = function() basename(rv$zip_path %||% "deployment.zip"),
    content = function(file) file.copy(rv$zip_path, file),
    contentType = "application/zip"
  )
}

shinyApp(ui, server)
