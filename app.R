# Posit Connect Cloud entry point.
# The main Publisher UI lives under build/publisher_ui so local Windows
# launchers can keep using the existing framework layout.
source(file.path("build", "publisher_ui", "app.R"), local = TRUE)$value
