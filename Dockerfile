FROM rocker/r-ver:4.4.3

ENV PORT=7860
ENV SHAREBRIDGE_FRAMEWORK_DIR=/app

WORKDIR /app

RUN R -e "install.packages(c('shiny', 'processx', 'jsonlite', 'renv'), repos = 'https://cloud.r-project.org')"

COPY . /app

EXPOSE 7860

CMD ["R", "-e", "shiny::runApp('/app/build/publisher_ui/app.R', host = '0.0.0.0', port = as.integer(Sys.getenv('PORT', '7860')))"]
