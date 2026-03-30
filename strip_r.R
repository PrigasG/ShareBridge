# strip_r.R
# ------------------------------------------------------------------
# Purpose:
#   Create a safer minimal portable R from a full R installation.
#
# Strategy:
#   - Copy the full R installation to framework_dir/R-portable-master
#   - Remove only clearly non-runtime content by default
#   - Optionally strip documentation from library packages
#   - Verify that R starts, shiny loads, and optional req.txt packages load
#   - Optionally refresh framework_dir/R-portable from the master copy
#
# Usage:
#   Rscript strip_r.R --r_source "C:/path/to/R-4.3.2"
#
# Optional flags:
#   --framework_dir     Where to put portable R folders (default: script parent dir)
#   --refresh_runtime   Also refresh framework_dir/R-portable from R-portable-master (default: TRUE)
#   --keep_tcltk      Keep Tcl/Tk runtime folders (default: FALSE)
#   --strip_pkg_docs  Strip docs from base/recommended library packages (default: TRUE)
#   --req_file        Optional req.txt to verify additional packages load
#   --dry_run         Show what would be done without copying (default: FALSE)
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
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return(character(0))
  x <- readLines(path, warn = FALSE)
  x <- trimws(x)
  x <- x[nzchar(x)]
  x <- x[!grepl("^\\s*#", x)]
  unique(x)
}

# ------------------------------------------------------------------
# Size utilities
# ------------------------------------------------------------------
dir_size_bytes <- function(path) {
  if (!dir.exists(path)) return(0)
  files <- list.files(path, recursive = TRUE, all.files = TRUE, full.names = TRUE, no.. = TRUE)
  if (!length(files)) return(0)
  info <- file.info(files, extra_cols = FALSE)
  sum(info$size[!is.na(info$size)], na.rm = TRUE)
}

format_size <- function(bytes) {
  if (is.na(bytes) || bytes < 1024) return(paste0(bytes, " B"))
  if (bytes < 1024^2) return(sprintf("%.1f KB", bytes / 1024))
  if (bytes < 1024^3) return(sprintf("%.1f MB", bytes / 1024^2))
  sprintf("%.2f GB", bytes / 1024^3)
}

# ------------------------------------------------------------------
# Safer default removals at R root
# ------------------------------------------------------------------
root_strip_dirs <- function() {
  c(
    "doc",
    "tests",
    "include",
    "src",
    "share/locale",
    "share/Rd",
    "share/doc"
  )
}

# ------------------------------------------------------------------
# Package doc content safe to remove
# ------------------------------------------------------------------
pkg_doc_dirs <- function() {
  c("help", "html", "doc", "demo", "examples", "man")
}

pkg_doc_files <- function() {
  c(
    "NEWS", "NEWS.md", "NEWS.Rd",
    "ChangeLog", "CHANGES",
    "README", "README.md",
    "CITATION",
    "TODO",
    "AUTHORS",
    "THANKS",
    "COPYRIGHTS",
    "LICENSE.note"
  )
}

strip_package_docs <- function(pkg_path, dry_run = FALSE) {
  stripped <- 0

  for (d in pkg_doc_dirs()) {
    dp <- file.path(pkg_path, d)
    if (dir.exists(dp)) {
      sz <- dir_size_bytes(dp)
      stripped <- stripped + sz
      if (!dry_run) unlink(dp, recursive = TRUE, force = TRUE)
    }
  }

  for (f in pkg_doc_files()) {
    fp <- file.path(pkg_path, f)
    if (file.exists(fp)) {
      sz <- file.info(fp, extra_cols = FALSE)$size
      if (!is.na(sz)) stripped <- stripped + sz
      if (!dry_run) unlink(fp, force = TRUE)
    }
  }

  stripped
}

# ------------------------------------------------------------------
# Copy full directory contents robustly
# ------------------------------------------------------------------
# ------------------------------------------------------------------
# Copy full directory contents robustly
# ------------------------------------------------------------------
copy_one_path <- function(src, dst, overwrite = TRUE, retries = 2L, wait_seconds = 0.25) {
  stopifnot(length(src) == 1L, length(dst) == 1L)

  src <- safe_norm(src, mustWork = TRUE)

  for (attempt in seq_len(retries + 1L)) {
    ok <- tryCatch({
      if (dir.exists(src)) {
        if (!dir.exists(dst)) {
          dir.create(dst, recursive = TRUE, showWarnings = FALSE)
        }
        TRUE
      } else {
        parent <- dirname(dst)
        if (!dir.exists(parent)) {
          dir.create(parent, recursive = TRUE, showWarnings = FALSE)
        }
        isTRUE(file.copy(
          from = src,
          to = dst,
          overwrite = overwrite,
          recursive = FALSE,
          copy.mode = TRUE,
          copy.date = TRUE
        ))
      }
    }, warning = function(w) {
      FALSE
    }, error = function(e) {
      FALSE
    })

    if (isTRUE(ok)) return(TRUE)

    if (attempt <= retries) Sys.sleep(wait_seconds)
  }

  FALSE
}

copy_dir_recursive <- function(src_dir, dst_dir, retries = 2L, wait_seconds = 0.25) {
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
    return(invisible(list(copied = character(0), failed = character(0))))
  }

  rel <- substring(entries, nchar(src_dir) + 2L)
  ord <- order(nchar(rel))
  entries <- entries[ord]
  rel <- rel[ord]

  failed <- character(0)
  copied <- character(0)

  for (i in seq_along(entries)) {
    src <- entries[[i]]
    dst <- file.path(dst_dir, rel[[i]])

    ok <- copy_one_path(
      src = src,
      dst = dst,
      overwrite = TRUE,
      retries = retries,
      wait_seconds = wait_seconds
    )

    if (isTRUE(ok)) {
      copied <- c(copied, rel[[i]])
    } else {
      failed <- c(failed, rel[[i]])
    }
  }

  if (length(failed)) {
    stop(
      "Failed to copy ", length(failed), " path(s). First failures: ",
      paste(utils::head(failed, 20), collapse = ", ")
    )
  }

  invisible(list(copied = copied, failed = failed))
}

copy_dir_contents <- function(src_dir, dst_dir, clean_dest = FALSE, retries = 2L, wait_seconds = 0.25) {
  src_dir <- safe_norm(src_dir, mustWork = TRUE)

  if (isTRUE(clean_dest) && dir.exists(dst_dir)) {
    unlink(dst_dir, recursive = TRUE, force = TRUE)
  }
  if (!dir.exists(dst_dir)) {
    dir.create(dst_dir, recursive = TRUE, showWarnings = FALSE)
  }

  top_items <- list.files(src_dir, all.files = TRUE, no.. = TRUE, full.names = TRUE)

  if (!length(top_items)) {
    return(invisible(TRUE))
  }

  failures <- character(0)

  for (src_item in top_items) {
    dst_item <- file.path(dst_dir, basename(src_item))

    ok <- tryCatch({
      if (dir.exists(src_item)) {
        copy_dir_recursive(
          src_dir = src_item,
          dst_dir = dst_item,
          retries = retries,
          wait_seconds = wait_seconds
        )
      } else {
        if (!copy_one_path(
          src = src_item,
          dst = dst_item,
          overwrite = TRUE,
          retries = retries,
          wait_seconds = wait_seconds
        )) {
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

# ------------------------------------------------------------------
# Detect an executable Rscript in a given R root
# ------------------------------------------------------------------
find_rscript <- function(r_root) {
  candidates <- c(
    file.path(r_root, "bin", "Rscript.exe"),
    file.path(r_root, "bin", "x64", "Rscript.exe"),
    file.path(r_root, "bin", "Rscript")
  )
  hits <- candidates[file.exists(candidates)]
  if (!length(hits)) return(NA_character_)
  safe_norm(hits[1], mustWork = TRUE)
}

find_r_exe <- function(r_root) {
  candidates <- c(
    file.path(r_root, "bin", "R.exe"),
    file.path(r_root, "bin", "x64", "R.exe"),
    file.path(r_root, "bin", "R")
  )
  hits <- candidates[file.exists(candidates)]
  if (!length(hits)) return(NA_character_)
  safe_norm(hits[1], mustWork = TRUE)
}

# ------------------------------------------------------------------
# Verification helpers
# ------------------------------------------------------------------
run_r_check <- function(rscript_path, expr, timeout = 60) {
  out <- tryCatch(
    system2(
      rscript_path,
      args = c("--vanilla", "-e", expr),
      stdout = TRUE,
      stderr = TRUE,
      timeout = timeout
    ),
    error = function(e) structure(conditionMessage(e), class = "check_error")
  )
  out
}

check_ok <- function(output, pattern = "^OK$") {
  is.character(output) && any(grepl(pattern, output))
}

verify_r_portable <- function(output_dir, req_pkgs = character(0)) {
  rscript_path <- find_rscript(output_dir)
  if (is.na(rscript_path)) {
    return(list(ok = FALSE, steps = list(
      r_start = FALSE,
      shiny = FALSE,
      req = FALSE
    ), details = "Rscript not found in stripped output."))
  }

  steps <- list(r_start = FALSE, shiny = FALSE, req = FALSE)
  details <- character(0)

  # 1. R starts
  out1 <- run_r_check(
    rscript_path,
    "cat('OK')",
    timeout = 20
  )
  steps$r_start <- check_ok(out1)
  if (!steps$r_start) details <- c(details, paste("R start check failed:", paste(out1, collapse = " | ")))

  # 2. shiny loads
  out2 <- run_r_check(
    rscript_path,
    "suppressPackageStartupMessages(library(shiny)); cat('OK')",
    timeout = 30
  )
  steps$shiny <- check_ok(out2)
  if (!steps$shiny) details <- c(details, paste("shiny load check failed:", paste(out2, collapse = " | ")))

  # 3. req packages load, if provided
  if (length(req_pkgs)) {
    expr <- paste0(
      "pkgs <- c(",
      paste(sprintf('"%s"', req_pkgs), collapse = ","),
      ");",
      "ok <- vapply(pkgs, function(p) {",
      "  suppressPackageStartupMessages(require(p, character.only = TRUE, quietly = TRUE));",
      "}, logical(1));",
      "if (all(ok)) cat('OK') else {",
      "  cat('FAIL:', paste(pkgs[!ok], collapse=','))",
      "}"
    )
    out3 <- run_r_check(rscript_path, expr, timeout = 120)
    steps$req <- check_ok(out3)
    if (!steps$req) details <- c(details, paste("req package load check failed:", paste(out3, collapse = " | ")))
  } else {
    steps$req <- TRUE
  }

  list(
    ok = all(unlist(steps)),
    steps = steps,
    details = paste(details, collapse = "\n")
  )
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
strip_r_main <- function(
    r_source,
    framework_dir = ".",
    keep_tcltk = FALSE,
    strip_pkg_docs = TRUE,
    req_file = NULL,
    dry_run = FALSE,
    refresh_runtime = TRUE
) {
  r_source <- safe_norm(r_source, mustWork = TRUE)
  framework_dir <- safe_norm(framework_dir, mustWork = TRUE)
  master_dir <- file.path(framework_dir, "R-portable-master")
  runtime_dir <- file.path(framework_dir, "R-portable")
  output_dir <- master_dir

  rscript_src <- find_rscript(r_source)
  r_exe_src <- find_r_exe(r_source)

  if (is.na(rscript_src) && is.na(r_exe_src)) {
    stop(
      "Cannot find R executables in: ", r_source, "\n",
      "Expected Rscript.exe or R.exe in bin/ or bin/x64/."
    )
  }

  r_version_str <- if (!is.na(rscript_src)) {
    out <- tryCatch(
      system2(
        rscript_src,
        args = c("--vanilla", "-e", "cat(paste(R.version$major, R.version$minor, sep='.'))"),
        stdout = TRUE,
        stderr = TRUE
      ),
      error = function(e) character(0)
    )

    if (length(out) == 0) {
      "unknown"
    } else {
      txt <- paste(out, collapse = " ")
      m <- regexpr("\\b[0-9]+\\.[0-9]+\\.[0-9]+\\b", txt)
      if (m[1] == -1) "unknown" else regmatches(txt, m)
    }
  } else {
    "unknown"
  }
  if (is.na(r_version_str) || !nzchar(r_version_str)) r_version_str <- "unknown"

  req_pkgs <- read_req_file(req_file)

  cat_line("[strip] Source R: ", r_source)
  cat_line("[strip] R version: ", r_version_str)
  cat_line("[strip] Master output: ", master_dir)
  cat_line("[strip] Runtime refresh: ", refresh_runtime)
  cat_line("[strip] Runtime dir: ", runtime_dir)
  cat_line("[strip] Keep Tcl/Tk runtime: ", keep_tcltk)
  cat_line("[strip] Strip package docs: ", strip_pkg_docs)
  cat_line("[strip] Verify req.txt packages: ", if (length(req_pkgs)) "YES" else "NO")
  cat_line("[strip] Dry run: ", dry_run)

  source_size <- dir_size_bytes(r_source)
  cat_line("[strip] Source size: ", format_size(source_size))

  if (dry_run) {
    cat_line("[strip] DRY RUN: no files will be copied or deleted.")
  }

  total_stripped <- 0

  # 1. Copy full R
  if (!dry_run) {
    if (dir.exists(master_dir)) {
      cat_line("[strip] Removing existing R-portable-master/")
      unlink(master_dir, recursive = TRUE, force = TRUE)
    }
    ensure_dir(master_dir)
    cat_line("[strip] Copying full R into R-portable-master/")
    copy_dir_contents(
      src_dir = r_source,
      dst_dir = master_dir,
      clean_dest = FALSE,
      retries = 2L,
      wait_seconds = 0.25
    )
  }

  # 2. Strip root documentation
  cat_line("[strip] Stripping root-level non-runtime content...")
  for (d in root_strip_dirs()) {
    dp <- file.path(output_dir, d)
    src_dp <- file.path(r_source, d)
    if (dir.exists(src_dp) || dir.exists(dp)) {
      sz <- if (dir.exists(dp)) dir_size_bytes(dp) else dir_size_bytes(src_dp)
      total_stripped <- total_stripped + sz
      cat_line("[strip]   Removing ", d, " (", format_size(sz), ")")
      if (!dry_run && dir.exists(dp)) unlink(dp, recursive = TRUE, force = TRUE)
    }
  }

  # 3. Optionally strip Tcl runtime directories
  if (!keep_tcltk) {
    for (d in c("Tcl", "Tcl64")) {
      dp <- file.path(output_dir, d)
      src_dp <- file.path(r_source, d)
      if (dir.exists(src_dp) || dir.exists(dp)) {
        sz <- if (dir.exists(dp)) dir_size_bytes(dp) else dir_size_bytes(src_dp)
        total_stripped <- total_stripped + sz
        cat_line("[strip]   Removing ", d, " (", format_size(sz), ")")
        if (!dry_run && dir.exists(dp)) unlink(dp, recursive = TRUE, force = TRUE)
      }
    }
  }

  # 4. Optionally strip package docs only
  pkg_doc_stripped <- 0
  lib_dir <- file.path(output_dir, "library")
  if (strip_pkg_docs && dir.exists(lib_dir)) {
    cat_line("[strip] Stripping docs from base/recommended packages...")
    pkg_dirs <- list.dirs(lib_dir, recursive = FALSE, full.names = TRUE)
    for (pkg_path in pkg_dirs) {
      sz <- strip_package_docs(pkg_path, dry_run = dry_run)
      pkg_doc_stripped <- pkg_doc_stripped + sz
    }
    total_stripped <- total_stripped + pkg_doc_stripped
    cat_line("[strip]   Package docs removed: ", format_size(pkg_doc_stripped))
  }

  # 5. Remove empty directories
  if (!dry_run && dir.exists(output_dir)) {
    dirs <- rev(sort(list.dirs(output_dir, recursive = TRUE, full.names = TRUE)))
    for (d in dirs) {
      if (identical(d, output_dir)) next
      if (!length(list.files(d, all.files = TRUE, no.. = TRUE))) {
        unlink(d, recursive = TRUE, force = TRUE)
      }
    }
  }

  final_size <- if (!dry_run && dir.exists(output_dir)) dir_size_bytes(output_dir) else max(source_size - total_stripped, 0)

  # 6. Verify
  verify <- list(ok = NA, steps = list(r_start = NA, shiny = NA, req = NA), details = "")
  if (!dry_run) {
    cat_line("[strip] Verifying stripped R...")
    verify <- verify_r_portable(output_dir, req_pkgs = req_pkgs)

    if (isTRUE(verify$ok)) {
      cat_line("[strip] Verification PASSED")
    } else {
      cat_line("[strip] Verification FAILED")
      if (nzchar(verify$details)) cat_line("[strip] ", verify$details)
    }
  }

  if (!dry_run && isTRUE(verify$ok) && isTRUE(refresh_runtime)) {
    cat_line("[strip] Refreshing runtime copy from R-portable-master to R-portable...")
    copy_dir_contents(
      src_dir = master_dir,
      dst_dir = runtime_dir,
      clean_dest = TRUE,
      retries = 2L,
      wait_seconds = 0.25
    )
  }

  # 7. Manifest
  manifest_path <- file.path(output_dir, "R_STRIP_MANIFEST.txt")
  manifest_lines <- c(
    "# R-portable strip manifest",
    paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")),
    paste0("# Source: ", r_source),
    paste0("# RVersion: ", r_version_str),
    paste0("# SourceSize: ", format_size(source_size)),
    paste0("# FinalSize: ", format_size(final_size)),
    paste0("# Removed: ", format_size(total_stripped)),
    paste0("# Reduction: ", if (source_size > 0) sprintf("%.0f%%", (total_stripped / source_size) * 100) else "0%"),
    paste0("# KeepTclTk: ", keep_tcltk),
    paste0("# StripPackageDocs: ", strip_pkg_docs),
    paste0("# Verified: ", if (!dry_run) verify$ok else NA),
    paste0("# Verify_R_Start: ", if (!dry_run) verify$steps$r_start else NA),
    paste0("# Verify_Shiny: ", if (!dry_run) verify$steps$shiny else NA),
    paste0("# Verify_Req: ", if (!dry_run) verify$steps$req else NA),
    if (nzchar(verify$details)) paste0("# Verify_Details: ", gsub("\n", " | ", verify$details)) else NULL,
    "",
    "# Removed by default:",
    "#   doc/, tests/, include/, src/, share/locale/, share/Rd/, share/doc/",
    if (!keep_tcltk) "#   Tcl/, Tcl64/" else "#   Tcl runtime kept",
    if (strip_pkg_docs) "#   package help/html/doc/demo/examples/man and doc-like text files" else "#   package docs kept"
  )

  if (!dry_run && dir.exists(output_dir)) {
    writeLines(manifest_lines[!vapply(manifest_lines, is.null, logical(1))], con = manifest_path, useBytes = TRUE)
  }

  cat_line("")
  cat_line("[strip] ============================================")
  cat_line("[strip] SUMMARY")
  cat_line("[strip] ============================================")
  cat_line("[strip] Source size: ", format_size(source_size))
  cat_line("[strip] Final size:  ", format_size(final_size))
  cat_line("[strip] Removed:     ", format_size(total_stripped),
           " (", if (source_size > 0) sprintf("%.0f%%", (total_stripped / source_size) * 100) else "0%", ")")
  cat_line("[strip] Output:      ", output_dir)
  if (!dry_run) {
    cat_line("[strip] Manifest:    ", manifest_path)
    cat_line("[strip] Verified:    ", if (isTRUE(verify$ok)) "YES" else "NO")
  }
  cat_line("[strip] ============================================")

  invisible(list(
    output_dir = output_dir,
    r_version = r_version_str,
    source_size = source_size,
    final_size = final_size,
    stripped = total_stripped,
    verified = if (!dry_run) verify$ok else NA,
    verify_steps = if (!dry_run) verify$steps else NULL,
    verify_details = if (!dry_run) verify$details else NULL,
    manifest = if (!dry_run) manifest_path else NULL
  ))
}

# ------------------------------------------------------------------
# CLI entry point
# ------------------------------------------------------------------
if (identical(environment(), globalenv()) && !length(sys.frames()) > 1) {
  args <- parse_args(commandArgs(trailingOnly = TRUE))

  r_source <- args$r_source %||% args$source %||% args$r
  if (is.null(r_source) || !nzchar(r_source)) {
    stop(
      "Please provide the path to a full R installation.\n",
      "Usage: Rscript strip_r.R --r_source \"C:/path/to/R-4.3.2\"\n",
      "\n",
      "Optional flags:\n",
      "  --framework_dir     Where to put portable R folders (default: script parent dir)\n",
      "  --keep_tcltk        Keep Tcl/Tk runtime (default: no)\n",
      "  --strip_pkg_docs    Strip docs from library packages (default: yes)\n",
      "  --req_file          Optional req.txt for verification\n",
      "  --refresh_runtime   Also refresh R-portable from R-portable-master (default: yes)\n",
      "  --dry_run           Show plan without copying\n"
    )
  }

  script_path <- tryCatch(
    normalizePath(sys.frames()[[1]]$ofile, winslash = "/", mustWork = TRUE),
    error = function(e) NULL
  )

  framework_dir <- if (!is.null(args$framework_dir)) {
    safe_norm(args$framework_dir, mustWork = TRUE)
  } else if (!is.null(script_path)) {
    safe_norm(file.path(dirname(script_path), ".."), mustWork = TRUE)
  } else {
    safe_norm(".", mustWork = TRUE)
  }

  strip_r_main(
    r_source = r_source,
    framework_dir = framework_dir,
    keep_tcltk = flag_value(args$keep_tcltk, FALSE),
    strip_pkg_docs = flag_value(args$strip_pkg_docs, TRUE),
    req_file = args$req_file %||% NULL,
    dry_run = flag_value(args$dry_run, FALSE),
    refresh_runtime = flag_value(args$refresh_runtime, TRUE)
  )
}
