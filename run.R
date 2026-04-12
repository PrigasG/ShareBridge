args <- commandArgs(trailingOnly = TRUE)
wd <- if (length(args) >= 1) args[1] else NA_character_
rd <- dirname(wd)

if (is.na(wd) || !nzchar(wd) || !dir.exists(wd)) {
  stop("Please use run.bat (or LaunchApp.hta) to launch the application.")
}

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || is.na(x) || !nzchar(as.character(x))) y else x
}

read_cfg <- function(path) {
  out <- list()
  if (!file.exists(path)) return(out)

  lines <- readLines(path, warn = FALSE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]
  lines <- lines[!grepl("^\\s*#", lines)]

  for (ln in lines) {
    if (!grepl("=", ln, fixed = TRUE)) next
    parts <- strsplit(ln, "=", fixed = TRUE)[[1]]
    key <- trimws(parts[1])
    val <- trimws(paste(parts[-1], collapse = "="))
    out[[key]] <- val
  }
  out
}

read_req_file <- function(path) {
  if (!file.exists(path)) return(character(0))
  x <- readLines(path, warn = FALSE)
  x <- trimws(x)
  x <- x[nzchar(x)]
  x <- x[!grepl("^\\s*#", x)]
  unique(x)
}

missing_from_libs <- function(pkgs, libs) {
  if (!length(pkgs)) return(character(0))
  ip <- installed.packages(lib.loc = libs)
  pkgs[!(pkgs %in% ip[, "Package"])]
}

pandoc_dir <- file.path(rd, "pandoc")
pandoc_exe <- file.path(pandoc_dir, "pandoc.exe")

if (file.exists(pandoc_exe)) {
  Sys.setenv(RSTUDIO_PANDOC = pandoc_dir)
  message(sprintf("[run] Using local Pandoc: %s", pandoc_dir))
} else {
  message(sprintf("[run] Local Pandoc not found at: %s", pandoc_dir))
}

cfg <- read_cfg(file.path(rd, "app_meta.cfg"))

app_name  <- Sys.getenv("APP_NAME", unset = cfg$APP_NAME %||% "Shiny App")
app_id    <- Sys.getenv("APP_ID", unset = cfg$APP_ID %||% "ShinyApp")
host      <- "127.0.0.1"
pref_port <- suppressWarnings(as.integer(cfg$PREFERRED_PORT %||% "3402"))
if (is.na(pref_port) || pref_port <= 0) pref_port <- 3402

# R version mismatch guard
version_file <- file.path(rd, "VERSION")
if (file.exists(version_file)) {
  ver_lines <- readLines(version_file, warn = FALSE)
  bundled_mm_match <- grep("^RVersionMajorMinor=", ver_lines, value = TRUE)
  if (length(bundled_mm_match)) {
    bundled_mm <- trimws(sub("^RVersionMajorMinor=", "", bundled_mm_match[1]))
    current_full <- paste(R.version$major, R.version$minor, sep = ".")
    current_mm   <- sub("^(\\d+\\.\\d+).*$", "\\1", current_full)
    if (nzchar(bundled_mm) && !identical(current_mm, bundled_mm)) {
      message(sprintf(
        "[run] WARNING: R version mismatch — deployment built with R %s, currently running R %s.",
        bundled_mm, current_mm
      ))
    } else if (nzchar(bundled_mm)) {
      message(sprintf("[run] R version OK: %s", current_mm))
    }
  }
}

# DATA_DIR — expose as env var if configured in app_meta.cfg
data_dir_cfg <- cfg$DATA_DIR %||% ""
if (nzchar(data_dir_cfg)) {
  Sys.setenv(SHAREBRIDGE_DATA_DIR = data_dir_cfg)
  message(sprintf("[run] DATA_DIR: %s", data_dir_cfg))
}

message(sprintf("[run] App: %s", app_name))
message(sprintf("[run] AppDir: %s", wd))

req <- read_req_file(file.path(rd, "req.txt"))

bundled_lib <- file.path(rd, "packages")
portable_lib <- file.path(rd, "R", "library")

lib_order <- character(0)
if (dir.exists(bundled_lib)) lib_order <- c(lib_order, bundled_lib)
if (dir.exists(portable_lib)) lib_order <- c(lib_order, portable_lib)
lib_order <- unique(c(lib_order, .libPaths()))
.libPaths(lib_order)

message(sprintf("[run] Library paths: %s", paste(.libPaths(), collapse = " | ")))

to_install <- missing_from_libs(req, .libPaths())

if (length(to_install) > 0) {
  local_repo <- file.path(rd, "repo")
  target_lib <- .libPaths()[1]

  message(sprintf("[run] Missing packages detected: %s", paste(to_install, collapse = ", ")))

  if (dir.exists(local_repo) && file.exists(file.path(local_repo, "PACKAGES"))) {
    message(sprintf("[run] Installing from local offline repo: %s", local_repo))
    install.packages(
      to_install,
      lib = target_lib,
      repos = local_repo,
      type = if (.Platform$OS.type == "windows") "win.binary" else "source",
      clean = TRUE
    )
  } else {
    message("[run] Local offline repo not found. Falling back to CRAN.")
    install.packages(
      to_install,
      lib = target_lib,
      repos = "https://cloud.r-project.org",
      clean = TRUE
    )
  }
}

still_missing <- missing_from_libs(req, .libPaths())
if (length(still_missing) > 0) {
  stop(
    sprintf(
      "The following required packages are still missing after installation attempt: %s",
      paste(still_missing, collapse = ", ")
    )
  )
}

suppressPackageStartupMessages(
  invisible(lapply(req, function(pkg) {
    library(pkg, character.only = TRUE, quietly = TRUE, warn.conflicts = FALSE)
  }))
)

Sys.setenv(SHINY_LOG_LEVEL = Sys.getenv("SHINY_LOG_LEVEL", unset = "INFO"))
options(shiny.fullstacktrace = TRUE)

#cool url ------------

make_launch_url <- function(port, app_id) {
  sprintf("http://sharebridge-%s.localhost:%d", tolower(app_id), as.integer(port))
}

run_on_port <- function(port) {
  browser_path <- file.path(rd, "chrome", "chrome.exe")
  launch_url <- make_launch_url(port, app_id)

  launch_fun <- NULL
  if (file.exists(browser_path)) {
    launch_fun <- function(shinyurl) {
      message(sprintf("[run] Launching browser at: %s", launch_url))
      system2(
        browser_path,
        args = c(sprintf("--app=%s", launch_url), "-incognito"),
        wait = FALSE
      )
    }
  } else {
    launch_fun <- function(shinyurl) {
      message(sprintf("[run] Launching browser at: %s", launch_url))
      utils::browseURL(launch_url)
    }
  }

  shiny::runApp(
    appDir = wd,
    host = host,
    port = port,
    launch.browser = launch_fun
  )
}

message(sprintf("[run] Trying preferred port %s:%d ...", host, pref_port))

tryCatch(
  run_on_port(pref_port),
  error = function(e) {
    message(sprintf("[run] Preferred port %d failed: %s", pref_port, conditionMessage(e)))
    alt <- httpuv::randomPort()
    message(sprintf("[run] Retrying on fallback port %s:%d ...", host, alt))
    run_on_port(alt)
  }
)
