FROM rocker/shiny:4.4.3

ENV PORT=7860
ENV SHAREBRIDGE_FRAMEWORK_DIR=/app

WORKDIR /app

RUN install2.r --error processx jsonlite renv

COPY . /app

EXPOSE 7860

CMD ["R", "-e", "shiny::runApp('/app/build/publisher_ui/app.R', host = '0.0.0.0', port = as.integer(Sys.getenv('PORT', '7860')))"]
