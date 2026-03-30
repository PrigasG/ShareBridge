# publish_app.R
# ------------------------------------------------------------------
# Purpose:
#   Assemble a ready-to-share Shiny deployment folder.
#
# Responsibilities:
#   - Validate source app structure
#   - Copy app into staged deployment folder
#   - Detect package dependencies
#   - Write req.txt
#   - Merge req_extra.txt if present
#   - Read optional app feature config
#   - Ensure writable app dirs exist when requested
#   - Write app_meta.cfg (name, ID, port, host)
#   - Create VERSION and README files
#   - Ensure logs/ exists
#   - Call build_packages.R to build bundled packages
#   - Optionally zip the final folder
# ------------------------------------------------------------------

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || is.na(x) || !nzchar(as.character(x))) y else x
}

parse_args <- function(x) {
  res <- list()
  i <- 1L
  while (i <= length(x)) {
    key <- x[[i]]
    if (startsWith(key, "--")) {
      key <- sub("^--", "", key)
      if (i == length(x) || startsWith(x[[i + 1L]], "--")) {
        res[[key]] <- TRUE
        i <- i + 1L
      } else {
        res[[key]] <- x[[i + 1L]]
        i <- i + 2L
      }
    } else {
      i <- i + 1L
    }
  }
  res
}

flag_value <- function(x, default = FALSE) {
  if (is.null(x)) return(default)
  if (is.logical(x)) return(isTRUE(x))
  tolower(as.character(x)) %in% c("1", "true", "yes", "y", "on")
}

cat_line <- function(...) cat(..., "\n")

safe_norm <- function(path, mustWork = FALSE) {
  normalizePath(path, winslash = "/", mustWork = mustWork)
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  safe_norm(path, mustWork = TRUE)
}

reset_dir <- function(path) {
  if (dir.exists(path)) unlink(path, recursive = TRUE, force = TRUE)
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  safe_norm(path, mustWork = TRUE)
}

read_req_file <- function(path) {
  if (!file.exists(path)) return(character(0))
  x <- readLines(path, warn = FALSE)
  x <- trimws(x)
  x <- x[nzchar(x)]
  x <- x[!grepl("^\\s*#", x)]
  unique(x)
}

write_req_file <- function(pkgs, path) {
  pkgs <- sort(unique(trimws(pkgs)))
  pkgs <- pkgs[nzchar(pkgs)]
  writeLines(pkgs, con = path, useBytes = TRUE)
}

detect_app_mode <- function(src_app_dir) {
  has_app <- file.exists(file.path(src_app_dir, "app.R"))
  has_ui  <- file.exists(file.path(src_app_dir, "ui.R"))
  has_srv <- file.exists(file.path(src_app_dir, "server.R"))

  if (has_app) return("app.R")
  if (has_ui && has_srv) return("ui_server")
  stop("Source app must contain either app.R or both ui.R and server.R.")
}

list_code_files <- function(app_dir) {
  candidates <- c(
    list.files(app_dir, pattern = "\\.[Rr]$", recursive = TRUE, full.names = TRUE),
    list.files(app_dir, pattern = "\\.[Rr]md$", recursive = TRUE, full.names = TRUE),
    list.files(app_dir, pattern = "\\.[Qq][Mm][Dd]$", recursive = TRUE, full.names = TRUE)
  )
  unique(candidates[file.exists(candidates)])
}

detect_dependencies_regex <- function(app_dir) {
  files <- list_code_files(app_dir)
  if (!length(files)) return(character(0))

  lines <- unlist(lapply(files, function(f) {
    tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))
  }), use.names = FALSE)

  lines <- gsub("#.*$", "", lines)

  pkgs <- character(0)

  m1 <- gregexpr("\\b(?:library|require)\\s*\\(\\s*['\"]?([A-Za-z][A-Za-z0-9._]*)['\"]?", lines, perl = TRUE)
  for (i in seq_along(m1)) {
    hits <- regmatches(lines[[i]], m1[[i]])[[1]]
    if (length(hits)) {
      vals <- sub("^.*\\(\\s*['\"]?([A-Za-z][A-Za-z0-9._]*)['\"]?.*$", "\\1", hits, perl = TRUE)
      pkgs <- c(pkgs, vals)
    }
  }

  m2 <- gregexpr("\\b([A-Za-z][A-Za-z0-9._]*)\\s*:::{0,2}\\s*[A-Za-z][A-Za-z0-9._]*", lines, perl = TRUE)
  for (i in seq_along(m2)) {
    hits <- regmatches(lines[[i]], m2[[i]])[[1]]
    if (length(hits)) {
      vals <- sub("^\\s*([A-Za-z][A-Za-z0-9._]*)\\s*:::{0,2}.*$", "\\1", hits, perl = TRUE)
      pkgs <- c(pkgs, vals)
    }
  }

  pkgs <- unique(pkgs)
  pkgs <- pkgs[!is.na(pkgs)]
  pkgs <- setdiff(pkgs, c(
    "base", "compiler", "datasets", "graphics", "grDevices",
    "grid", "methods", "parallel", "splines", "stats",
    "stats4", "tcltk", "tools", "utils"
  ))
  sort(pkgs)
}

detect_dependencies <- function(app_dir) {
  if (requireNamespace("renv", quietly = TRUE)) {
    deps <- tryCatch(
      renv::dependencies(
        path = app_dir,
        root = app_dir,
        progress = FALSE,
        errors = "reported"
      ),
      error = function(e) NULL
    )

    if (!is.null(deps) && NROW(deps) > 0 && "Package" %in% names(deps)) {
      pkgs <- deps$Package
      pkgs <- pkgs[!is.na(pkgs)]
      pkgs <- unique(pkgs)
      pkgs <- setdiff(pkgs, c(
        "base", "compiler", "datasets", "graphics", "grDevices",
        "grid", "methods", "parallel", "splines", "stats",
        "stats4", "tcltk", "tools", "utils"
      ))
      return(sort(pkgs))
    }
  }

  detect_dependencies_regex(app_dir)
}

# pandoc builder ----
ensure_pandoc_stub <- function(output_dir) {
  pandoc_dir <- file.path(output_dir, "pandoc")
  if (!dir.exists(pandoc_dir)) {
    dir.create(pandoc_dir, recursive = TRUE, showWarnings = FALSE)
  }

  readme <- file.path(pandoc_dir, "README_Pandoc.txt")
  writeLines(c(
    "Pandoc support",
    "",
    "If this app needs PDF or R Markdown rendering with Pandoc,",
    "install Pandoc into this folder.",
    "",
    "Expected executable:",
    "pandoc/pandoc.exe",
    "",
    "After installing, LaunchApp will use this local Pandoc folder if present."
  ), readme, useBytes = TRUE)

  invisible(pandoc_dir)
}

# ------------------------------------------------------------------
# App feature helpers
# ------------------------------------------------------------------
default_app_features <- function() {
  list(
    enable_write_mode = FALSE,
    writable_dirs = character(0),
    include_pandoc = FALSE,
    bundle_rmarkdown_support = FALSE
  )
}

as_character_vector <- function(x) {
  if (is.null(x)) return(character(0))
  x <- unlist(x, use.names = FALSE)
  x <- trimws(as.character(x))
  unique(x[nzchar(x)])
}

read_app_features_file <- function(path = NULL) {
  features <- default_app_features()

  if (is.null(path) || !nzchar(path)) {
    return(features)
  }

  if (!file.exists(path)) {
    stop("app_features_file does not exist: ", path)
  }

  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("The jsonlite package is required to read app_features_file.")
  }

  raw <- tryCatch(
    jsonlite::read_json(path, simplifyVector = TRUE),
    error = function(e) stop("Failed to read app_features_file: ", conditionMessage(e))
  )

  if (!is.list(raw)) {
    stop("app_features_file must contain a JSON object.")
  }

  features$enable_write_mode <- isTRUE(raw$enable_write_mode)
  features$writable_dirs <- as_character_vector(raw$writable_dirs)
  features$include_pandoc <- isTRUE(raw$include_pandoc)
  features$bundle_rmarkdown_support <- isTRUE(raw$bundle_rmarkdown_support)

  features
}

normalize_relative_subdirs <- function(paths) {
  paths <- as_character_vector(paths)
  if (!length(paths)) return(character(0))

  parts <- strsplit(paths, "[/\\\\]+")
  normalized <- vapply(parts, function(seg) {
    seg <- trimws(seg)
    seg <- seg[nzchar(seg)]
    seg <- seg[seg != "."]
    if (!length(seg)) return(NA_character_)
    if (any(seg == "..")) {
      stop("writable_dirs may not contain '..' path traversal segments.")
    }
    paste(seg, collapse = "/")
  }, character(1), USE.NAMES = FALSE)

  normalized <- normalized[!is.na(normalized) & nzchar(normalized)]
  unique(normalized)
}

ensure_app_writable_dirs <- function(app_dir, writable_dirs) {
  writable_dirs <- normalize_relative_subdirs(writable_dirs)
  if (!length(writable_dirs)) {
    return(character(0))
  }

  created <- character(0)

  for (rel in writable_dirs) {
    target <- file.path(app_dir, strsplit(rel, "/", fixed = TRUE)[[1]])
    if (!dir.exists(target)) {
      dir.create(target, recursive = TRUE, showWarnings = FALSE)
    }
    if (!dir.exists(target)) {
      stop("Failed to create writable app directory: ", rel)
    }
    created <- c(created, safe_norm(target, mustWork = TRUE))
  }

  created
}

pandoc_support_packages <- function(bundle_rmarkdown_support = FALSE) {
  pkgs <- c("rmarkdown")
  if (isTRUE(bundle_rmarkdown_support)) {
    pkgs <- c(pkgs, "knitr", "markdown", "htmltools", "yaml")
  }
  sort(unique(pkgs))
}

# ------------------------------------------------------------------
# Port assignment
# ------------------------------------------------------------------
derive_port <- function(app_id, range_start = 3400L, range_size = 1001L) {
  raw <- charToRaw(app_id)
  hash <- sum(as.integer(raw) * seq_along(raw)) %% range_size
  as.integer(range_start + hash)
}

# ------------------------------------------------------------------
# app_meta.cfg
# ------------------------------------------------------------------
write_app_meta <- function(path, app_name, app_id, preferred_port = 3402L, host = "127.0.0.1") {
  lines <- c(
    paste0("APP_NAME=", app_name),
    paste0("APP_ID=", app_id),
    paste0("PREFERRED_PORT=", preferred_port),
    paste0("HOST=", host)
  )
  writeLines(lines, con = path, useBytes = TRUE)
}

make_app_id <- function(app_name) {
  id <- gsub("[^A-Za-z0-9_]+", "_", app_name)
  id <- gsub("_+", "_", id)
  id <- gsub("^_|_$", "", id)
  id
}

# ------------------------------------------------------------------
# Read R version from the portable R strip manifest
# ------------------------------------------------------------------
read_portable_r_version <- function(r_portable_dir) {
  manifest <- file.path(r_portable_dir, "R_STRIP_MANIFEST.txt")
  if (!file.exists(manifest)) return(NA_character_)
  lines <- readLines(manifest, warn = FALSE)
  ver_line <- grep("^# RVersion:", lines, value = TRUE)
  if (!length(ver_line)) return(NA_character_)
  trimws(sub("^# RVersion:\\s*", "", ver_line[1]))
}

write_version_file <- function(path, app_name, detected_pkgs, r_version = NULL) {
  if (is.null(r_version) || !nzchar(r_version) || identical(r_version, "unknown")) {
    r_version <- paste(R.version$major, R.version$minor, sep = ".")
  }
  r_major_minor <- sub("^(\\d+\\.\\d+).*$", "\\1", r_version)

  lines <- c(
    paste0("AppName=", app_name),
    paste0("BuiltAt=", format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")),
    paste0("RVersion=", r_version),
    paste0("RVersionMajorMinor=", r_major_minor),
    paste0("Platform=", R.version$platform),
    paste0("PackageCount=", length(detected_pkgs)),
    paste0("HasPortableR=", "true")
  )
  writeLines(lines, con = path, useBytes = TRUE)
}

write_readmes <- function(output_dir, app_name) {
  user_readme <- file.path(output_dir, "README_User.txt")
  publisher_readme <- file.path(output_dir, "README_Publisher.txt")

  writeLines(c(
    app_name,
    "",
    "How to use:",
    "1. Sync this folder from SharePoint to your computer.",
    "2. Open the synced folder after sync finishes.",
    "3. Double-click LaunchApp.hta to launch the app.",
    "",
    "Optional:",
    "Create a desktop shortcut to LaunchApp.hta."
  ), con = user_readme, useBytes = TRUE)

  writeLines(c(
    app_name,
    "",
    "Publisher Instructions:",
    "1. Put the Shiny app files in the source folder.",
    "2. Run publish_app.R.",
    "3. Copy the completed folder to SharePoint.",
    "4. Tell users to sync and run LaunchApp.hta."
  ), con = publisher_readme, useBytes = TRUE)
}

# ------------------------------------------------------------------
# Copy helpers
# ------------------------------------------------------------------
is_windows <- function() {
  identical(.Platform$OS.type, "windows")
}

copy_file_with_retries <- function(src, dst, retries = 2L, wait_seconds = 0.25) {
  src <- safe_norm(src, mustWork = TRUE)

  parent <- dirname(dst)
  if (!dir.exists(parent)) dir.create(parent, recursive = TRUE, showWarnings = FALSE)

  for (attempt in seq_len(retries + 1L)) {
    ok <- tryCatch(
      isTRUE(file.copy(src, dst, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE)),
      warning = function(w) FALSE,
      error = function(e) FALSE
    )
    if (ok) return(TRUE)
    if (attempt <= retries) Sys.sleep(wait_seconds)
  }

  FALSE
}


copy_dir_recursive_r <- function(src_dir, dst_dir, retries = 2L, wait_seconds = 0.25) {
  src_dir <- safe_norm(src_dir, mustWork = TRUE)

  if (!dir.exists(src_dir)) {
    stop("Source directory does not exist: ", src_dir)
  }

  if (!dir.exists(dst_dir)) {
    dir.create(dst_dir, recursive = TRUE, showWarnings = FALSE)
  }

  entries <- list.files(
    src_dir,
    all.files = TRUE,
    no.. = TRUE,
    recursive = TRUE,
    full.names = TRUE,
    include.dirs = TRUE
  )

  if (!length(entries)) {
    return(invisible(TRUE))
  }

  rel <- substring(entries, nchar(src_dir) + 2L)
  ord <- order(nchar(rel))
  entries <- entries[ord]
  rel <- rel[ord]

  failed <- character(0)

  for (i in seq_along(entries)) {
    src <- entries[[i]]
    dst <- file.path(dst_dir, rel[[i]])

    if (dir.exists(src)) {
      if (!dir.exists(dst)) {
        dir.create(dst, recursive = TRUE, showWarnings = FALSE)
      }
      if (!dir.exists(dst)) {
        failed <- c(failed, rel[[i]])
      }
    } else {
      ok <- copy_file_with_retries(src, dst, retries = retries, wait_seconds = wait_seconds)
      if (!ok) {
        failed <- c(failed, rel[[i]])
      }
    }
  }

  if (length(failed)) {
    stop(
      "Failed to copy ", length(failed), " path(s). First failures: ",
      paste(utils::head(failed, 20), collapse = ", ")
    )
  }

  invisible(TRUE)
}

copy_dir_robocopy <- function(src_dir, dst_dir, mirror = FALSE) {
  src_dir <- safe_norm(src_dir, mustWork = TRUE)

  if (!dir.exists(src_dir)) {
    stop("Source directory does not exist: ", src_dir)
  }

  if (dir.exists(dst_dir) && isTRUE(mirror)) {
    unlink(dst_dir, recursive = TRUE, force = TRUE)
  }
  if (!dir.exists(dst_dir)) {
    dir.create(dst_dir, recursive = TRUE, showWarnings = FALSE)
  }

  src_native <- normalizePath(src_dir, winslash = "\\", mustWork = TRUE)
  dst_native <- normalizePath(dst_dir, winslash = "\\", mustWork = FALSE)

  robocopy_args <- c(
    shQuote(src_native, type = "cmd"),
    shQuote(dst_native, type = "cmd"),
    "/E",
    "/COPY:DAT",
    "/DCOPY:DAT",
    "/R:2",
    "/W:1",
    "/NFL",
    "/NDL",
    "/NJH",
    "/NJS",
    "/NP"
  )

  cmd_line <- paste("robocopy", paste(robocopy_args, collapse = " "))

  res <- suppressWarnings(
    system2("cmd.exe", args = c("/c", cmd_line), stdout = TRUE, stderr = TRUE)
  )

  status <- attr(res, "status")
  if (is.null(status)) status <- 0L

  cat_line("[copy] robocopy command: ", cmd_line)
  cat_line("[copy] robocopy exit code: ", status)

  if (length(res)) {
    for (line in res) {
      if (nzchar(trimws(line))) cat_line("[copy] ", line)
    }
  }

  if (as.integer(status) >= 8L) {
    stop("robocopy failed with exit code ", status)
  }

  invisible(TRUE)
}

copy_dir_contents <- function(src_dir, dst_dir, clean_dest = FALSE, use_robocopy = FALSE,
                              retries = 2L, wait_seconds = 0.25) {
  src_dir <- safe_norm(src_dir, mustWork = TRUE)

  if (isTRUE(clean_dest) && dir.exists(dst_dir)) {
    unlink(dst_dir, recursive = TRUE, force = TRUE)
  }
  if (!dir.exists(dst_dir)) {
    dir.create(dst_dir, recursive = TRUE, showWarnings = FALSE)
  }

  if (isTRUE(use_robocopy) && is_windows()) {
    return(copy_dir_robocopy(src_dir, dst_dir, mirror = FALSE))
  }

  top_items <- list.files(src_dir, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  if (!length(top_items)) return(invisible(TRUE))

  failures <- character(0)

  for (src_item in top_items) {
    dst_item <- file.path(dst_dir, basename(src_item))

    ok <- tryCatch({
      if (dir.exists(src_item)) {
        copy_dir_recursive_r(
          src_dir = src_item,
          dst_dir = dst_item,
          retries = retries,
          wait_seconds = wait_seconds
        )
      } else {
        if (!copy_file_with_retries(src_item, dst_item, retries = retries, wait_seconds = wait_seconds)) {
          stop("file copy failed")
        }
      }
      TRUE
    }, error = function(e) {
      cat_line("[copy] failed: ", src_item)
      cat_line("[copy] reason: ", conditionMessage(e))
      FALSE
    })

    if (!isTRUE(ok)) {
      failures <- c(failures, basename(src_item))
    }
  }

  if (length(failures)) {
    stop("Failed to copy some source items: ", paste(failures, collapse = ", "))
  }

  invisible(TRUE)
}

zip_dir <- function(dir_path, zipfile) {
  oldwd <- getwd()
  on.exit(setwd(oldwd), add = TRUE)
  setwd(dirname(dir_path))
  base <- basename(dir_path)

  if (file.exists(zipfile)) unlink(zipfile, force = TRUE)

  old <- list.files(base, recursive = TRUE, all.files = TRUE, no.. = TRUE, include.dirs = FALSE)
  utils::zip(zipfile = zipfile, files = file.path(base, old), extras = "-r9X")
}

publish_app_main <- function(
    source_dir,
    output_dir,
    app_name = NULL,
    framework_dir = ".",
    req_extra_file = NULL,
    app_features_file = NULL,
    zip_output = FALSE,
    build_offline_repo = FALSE,
    cran_repo = "https://cloud.r-project.org",
    verify_load = TRUE,
    preferred_port = NULL,
    host = "127.0.0.1"
) {
  framework_dir <- safe_norm(framework_dir, mustWork = TRUE)
  source_dir <- safe_norm(source_dir, mustWork = TRUE)

  if (is.null(app_name) || !nzchar(app_name)) {
    app_name <- basename(output_dir)
  }

  app_features <- read_app_features_file(app_features_file)
  app_features$writable_dirs <- normalize_relative_subdirs(app_features$writable_dirs)

  app_id <- make_app_id(app_name)

  if (is.null(preferred_port)) {
    preferred_port <- derive_port(app_id)
  }
  preferred_port <- as.integer(preferred_port)

  cat_line("[publish] Framework dir: ", framework_dir)
  cat_line("[publish] Source app:    ", source_dir)
  cat_line("[publish] Output dir:    ", output_dir)
  cat_line("[publish] App name:      ", app_name)
  cat_line("[publish] App ID:        ", app_id)
  cat_line("[publish] Preferred port:", preferred_port)
  cat_line("[publish] enable_write_mode: ", app_features$enable_write_mode)
  cat_line("[publish] writable_dirs: ", paste(app_features$writable_dirs, collapse = ", "))
  cat_line("[publish] include_pandoc: ", app_features$include_pandoc)
  cat_line("[publish] bundle_rmarkdown_support: ", app_features$bundle_rmarkdown_support)

  required_framework_files <- c("LaunchApp.hta", "run.bat", "run.R")
  missing_framework <- required_framework_files[
    !file.exists(file.path(framework_dir, required_framework_files))
  ]
  if (length(missing_framework)) {
    stop("Missing required framework files: ", paste(missing_framework, collapse = ", "))
  }

  build_script <- file.path(framework_dir, "build", "build_packages.R")
  if (!file.exists(build_script)) {
    stop("Missing build/build_packages.R in framework directory.")
  }

  mode <- detect_app_mode(source_dir)
  cat_line("[publish] App mode detected: ", mode)

  output_dir <- reset_dir(output_dir)
  cat_line("[publish] Output dir reset complete.")
  cat_line("[publish] Output dir exists: ", dir.exists(output_dir))

  ensure_dir(output_dir)
  ensure_dir(file.path(output_dir, "app"))
  ensure_dir(file.path(output_dir, "logs"))
  ensure_dir(file.path(output_dir, "build"))

  for (f in required_framework_files) {
    file.copy(file.path(framework_dir, f), file.path(output_dir, f), overwrite = TRUE)
  }

  file.copy(build_script, file.path(output_dir, "build", "build_packages.R"), overwrite = TRUE)

  r_portable_src_candidates <- c(
    file.path(framework_dir, "R-portable-master"),
    file.path(framework_dir, "R-portable")
  )

  existing_candidates <- r_portable_src_candidates[dir.exists(r_portable_src_candidates)]

  if (length(existing_candidates)) {
    r_portable_src <- existing_candidates[1]
  } else {
    r_portable_src <- file.path(framework_dir, "R-portable")
  }

  portable_r_version <- NA_character_
  cat_line("[publish] Portable R source: ", r_portable_src)

  if (dir.exists(r_portable_src)) {
    cat_line("[publish] Portable R top-level entries: ",
             paste(list.files(r_portable_src, all.files = TRUE, no.. = TRUE), collapse = ", "))

    r_dest <- file.path(output_dir, "R")

    withCallingHandlers(
      {
        copy_dir_contents(
          src_dir = r_portable_src,
          dst_dir = r_dest,
          clean_dest = TRUE,
          use_robocopy = TRUE,
          retries = 3L,
          wait_seconds = 0.5
        )
      },
      warning = function(w) {
        cat_line("[copy warning] ", conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )

    portable_r_version <- read_portable_r_version(r_portable_src)
    cat_line("[publish] Portable R version: ", portable_r_version %||% "unknown")
  } else {
    cat_line("[publish] WARNING: No R-portable-master/ or R-portable/ found in framework directory.")
    cat_line("[publish]   Users will need R installed on their system.")
    cat_line("[publish]   Run strip_r.R first to create portable R.")
  }

  write_app_meta(
    path = file.path(output_dir, "app_meta.cfg"),
    app_name = app_name,
    app_id = app_id,
    preferred_port = preferred_port,
    host = host
  )
  cat_line("[publish] app_meta.cfg written.")

  app_out_dir <- file.path(output_dir, "app")
  copy_dir_contents(
    src_dir = source_dir,
    dst_dir = app_out_dir,
    clean_dest = FALSE,
    use_robocopy = FALSE,
    retries = 2L,
    wait_seconds = 0.25
  )

  created_writable_dirs <- character(0)
  if (isTRUE(app_features$enable_write_mode) && length(app_features$writable_dirs)) {
    cat_line("[publish] Ensuring writable app dirs exist...")
    created_writable_dirs <- ensure_app_writable_dirs(app_out_dir, app_features$writable_dirs)
    cat_line("[publish] Writable dirs ready: ", paste(app_features$writable_dirs, collapse = ", "))
  }

  detected_pkgs <- detect_dependencies(app_out_dir)
  detected_pkgs <- unique(c("shiny", detected_pkgs))

  extra_req <- character(0)
  extra_candidates <- c(
    req_extra_file,
    file.path(source_dir, "req_extra.txt"),
    file.path(framework_dir, "req_extra.txt")
  )

  for (p in extra_candidates) {
    if (!is.null(p) && file.exists(p)) {
      extra_req <- unique(c(extra_req, read_req_file(p)))
    }
  }

  # if (isTRUE(app_features$include_pandoc)) {
  #   pandoc_pkgs <- pandoc_support_packages(app_features$bundle_rmarkdown_support)
  #   cat_line("[publish] Adding Pandoc support packages: ", paste(pandoc_pkgs, collapse = ", "))
  #   extra_req <- unique(c(extra_req, pandoc_pkgs))
  # }

  if (isTRUE(app_features$include_pandoc)) {
    pandoc_dir <- ensure_pandoc_stub(output_dir)
    cat_line("[publish] Pandoc folder prepared at: ", pandoc_dir)

    pandoc_pkgs <- pandoc_support_packages(app_features$bundle_rmarkdown_support)
    cat_line("[publish] Adding Pandoc support packages: ", paste(pandoc_pkgs, collapse = ", "))
    extra_req <- unique(c(extra_req, pandoc_pkgs))
  }

  final_req <- sort(unique(c(detected_pkgs, extra_req)))
  write_req_file(final_req, file.path(output_dir, "req.txt"))

  cat_line("[publish] req.txt written with ", length(final_req), " packages.")
  cat_line("[publish] Packages: ", paste(final_req, collapse = ", "))

  write_version_file(
    path = file.path(output_dir, "VERSION"),
    app_name = app_name,
    detected_pkgs = final_req,
    r_version = portable_r_version
  )

  write_readmes(output_dir, app_name)

  build_env <- new.env(parent = globalenv())
  sys.source(file.path(output_dir, "build", "build_packages.R"), envir = build_env)

  if (!exists("build_packages_main", envir = build_env, inherits = FALSE)) {
    stop("build_packages_main() not found after sourcing build_packages.R")
  }

  cat_line("[publish] Building bundled package library...")
  build_result <- build_env$build_packages_main(
    project_dir = output_dir,
    req_file = "req.txt",
    bundled_lib_dir = "packages",
    build_offline_repo = build_offline_repo,
    offline_repo_dir = "repo",
    cran_repo = cran_repo,
    install_dependencies = TRUE,
    verify_load = verify_load
  )

  if (isTRUE(zip_output)) {
    zipfile <- paste0(output_dir, ".zip")
    cat_line("[publish] Creating zip: ", zipfile)
    zip_dir(output_dir, zipfile)
  }

  cat_line("[publish] Done.")
  invisible(list(
    output_dir = output_dir,
    zipfile = if (isTRUE(zip_output)) paste0(output_dir, ".zip") else NULL,
    req = final_req,
    build = build_result,
    app_meta = list(
      app_name = app_name,
      app_id = app_id,
      preferred_port = preferred_port,
      host = host
    ),
    app_features = list(
      enable_write_mode = app_features$enable_write_mode,
      writable_dirs = app_features$writable_dirs,
      include_pandoc = app_features$include_pandoc,
      bundle_rmarkdown_support = app_features$bundle_rmarkdown_support,
      created_writable_dirs = created_writable_dirs
    ),
    portable_r = list(
      bundled = dir.exists(file.path(output_dir, "R")),
      version = portable_r_version
    )
  ))
}

if (identical(environment(), globalenv()) && !length(sys.frames()) > 1) {
  args <- parse_args(commandArgs(trailingOnly = TRUE))

  script_path <- tryCatch(
    normalizePath(sys.frames()[[1]]$ofile, winslash = "/", mustWork = TRUE),
    error = function(e) NULL
  )

  framework_dir <- if (!is.null(args$framework_dir) && nzchar(args$framework_dir)) {
    safe_norm(args$framework_dir, mustWork = TRUE)
  } else if (!is.null(script_path)) {
    safe_norm(file.path(dirname(script_path), ".."), mustWork = TRUE)
  } else {
    safe_norm(".", mustWork = TRUE)
  }

  source_dir <- args$source_dir %||% args$source
  if (is.null(source_dir) || !nzchar(source_dir)) {
    stop("Please provide --source_dir or --source")
  }

  output_dir <- args$output_dir %||% args$output %||%
    file.path(framework_dir, "dist", "ShareBridge_App")

  publish_app_main(
    source_dir = source_dir,
    output_dir = output_dir,
    app_name = args$app_name %||% basename(output_dir),
    framework_dir = framework_dir,
    req_extra_file = args$req_extra_file %||% NULL,
    app_features_file = args$app_features_file %||% NULL,
    zip_output = flag_value(args$zip_output %||% args$zip, FALSE),
    build_offline_repo = flag_value(args$build_offline_repo, FALSE),
    cran_repo = args$cran_repo %||% "https://cloud.r-project.org",
    verify_load = flag_value(args$verify_load, TRUE),
    preferred_port = if (!is.null(args$preferred_port)) as.integer(args$preferred_port) else NULL,
    host = args$host %||% "127.0.0.1"
  )
}
