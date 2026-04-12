# build_packages.R
# ------------------------------------------------------------------
# Purpose:
#   Build a bundled R package library for a staged Shiny deployment.
#
# Responsibilities:
#   - Read req.txt
#   - Install required packages into ./packages
#   - Optionally create ./repo as an offline package repo
#   - Verify packages load successfully
#   - Write packages_manifest.tsv
#
# Can be used:
#   - directly from command line
#   - sourced and called from publish_app.R
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

read_req <- function(path) {
  if (!file.exists(path)) stop("req.txt not found at: ", path)
  x <- readLines(path, warn = FALSE)
  x <- trimws(x)
  x <- x[nzchar(x)]
  x <- x[!grepl("^\\s*#", x)]
  unique(x)
}

missing_from_lib <- function(pkgs, lib.loc) {
  if (!length(pkgs)) return(character(0))
  ip <- installed.packages(lib.loc = lib.loc)
  pkgs[!(pkgs %in% ip[, "Package"])]
}

pkg_versions <- function(pkgs, lib.loc) {
  ip <- installed.packages(lib.loc = lib.loc)
  have <- intersect(pkgs, ip[, "Package"])
  data.frame(
    Package = have,
    Version = unname(ip[have, "Version"]),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

write_manifest <- function(path, pkgs, lib.loc, build_repo, repo_path = NA_character_) {
  ver_tbl <- pkg_versions(pkgs, lib.loc)

  header <- c(
    "# Package bundle manifest",
    paste0("# BuiltAt: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")),
    paste0("# R.Version: ", paste(R.version$major, R.version$minor, sep = ".")),
    paste0("# Platform: ", R.version$platform),
    paste0("# BundledLib: ", lib.loc),
    paste0("# OfflineRepoEnabled: ", build_repo),
    paste0("# OfflineRepoPath: ", repo_path),
    ""
  )

  writeLines(header, con = path, useBytes = TRUE)
  utils::write.table(
    ver_tbl,
    file = path,
    sep = "\t",
    row.names = FALSE,
    quote = FALSE,
    append = TRUE
  )
}

build_packages_main <- function(
    project_dir = ".",
    req_file = "req.txt",
    bundled_lib_dir = "packages",
    build_offline_repo = FALSE,
    offline_repo_dir = "repo",
    cran_repo = "https://cloud.r-project.org",
    install_dependencies = TRUE,
    verify_load = TRUE
) {
  project_dir <- safe_norm(project_dir, mustWork = TRUE)
  oldwd <- getwd()
  on.exit(setwd(oldwd), add = TRUE)
  setwd(project_dir)

  options(repos = c(CRAN = cran_repo))

  req_path <- file.path(project_dir, req_file)
  bundled_path <- ensure_dir(file.path(project_dir, bundled_lib_dir))
  repo_path <- file.path(project_dir, offline_repo_dir)

  req <- read_req(req_path)

  cat_line("[build] Project dir: ", project_dir)
  cat_line("[build] req.txt:     ", req_path)
  cat_line("[build] packages/:   ", bundled_path)
  cat_line("[build] Requested packages: ", length(req))

  .libPaths(c(bundled_path, .libPaths()))

  to_install <- missing_from_lib(req, bundled_path)
  if (length(to_install)) {
    cat_line("[build] Installing missing packages into bundled library:")
    cat_line("[build] ", paste(to_install, collapse = ", "))

    install.packages(
      to_install,
      lib = bundled_path,
      repos = cran_repo,
      type = if (identical(.Platform$OS.type, "windows")) "win.binary" else "source",
      dependencies = install_dependencies,
      clean = TRUE
    )
  } else {
    cat_line("[build] All requested packages already present in bundled library.")
  }

  still_missing <- missing_from_lib(req, bundled_path)
  if (length(still_missing)) {
    stop(
      "Some packages are still missing after installation: ",
      paste(still_missing, collapse = ", ")
    )
  }

  if (verify_load) {
    cat_line("[build] Verifying package loadability from bundled library...")
    load_fail <- character(0)

    for (p in req) {
      ok <- suppressWarnings(
        suppressMessages(
          require(p, character.only = TRUE, quietly = TRUE, lib.loc = bundled_path)
        )
      )
      if (!isTRUE(ok)) load_fail <- c(load_fail, p)
    }

    if (length(load_fail)) {
      stop(
        "Load verification failed for: ",
        paste(load_fail, collapse = ", ")
      )
    }

    cat_line("[build] Load verification OK.")
  }

  if (isTRUE(build_offline_repo)) {
    ensure_dir(repo_path)
    cat_line("[build] Creating offline repo in: ", repo_path)

    dl_type <- if (identical(.Platform$OS.type, "windows")) "win.binary" else "source"

    ip <- installed.packages(lib.loc = bundled_path)
    present_pkgs <- ip[, "Package"]

    utils::download.packages(
      pkgs = present_pkgs,
      destdir = repo_path,
      type = dl_type,
      repos = cran_repo
    )

    tools::write_PACKAGES(repo_path, type = dl_type)
    cat_line("[build] Offline repo created.")
  }

  manifest_path <- file.path(project_dir, "packages_manifest.tsv")
  write_manifest(
    path = manifest_path,
    pkgs = req,
    lib.loc = bundled_path,
    build_repo = isTRUE(build_offline_repo),
    repo_path = if (dir.exists(repo_path)) safe_norm(repo_path, mustWork = TRUE) else NA_character_
  )

  cat_line("[build] Wrote manifest: ", manifest_path)
  cat_line("[build] Done.")

  invisible(list(
    project_dir = project_dir,
    req = req,
    bundled_lib = bundled_path,
    offline_repo = if (dir.exists(repo_path)) safe_norm(repo_path, mustWork = TRUE) else NULL,
    manifest = manifest_path
  ))
}

if (identical(environment(), globalenv()) && !length(sys.frames()) > 1) {
  args <- parse_args(commandArgs(trailingOnly = TRUE))

  build_packages_main(
    project_dir = args$project_dir %||% ".",
    req_file = args$req_file %||% "req.txt",
    bundled_lib_dir = args$bundled_lib_dir %||% "packages",
    build_offline_repo = flag_value(args$build_offline_repo, FALSE),
    offline_repo_dir = args$offline_repo_dir %||% "repo",
    cran_repo = args$cran_repo %||% "https://cloud.r-project.org",
    install_dependencies = flag_value(args$install_dependencies, TRUE),
    verify_load = flag_value(args$verify_load, TRUE)
  )
}
