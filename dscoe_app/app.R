
# Load packages
library(shiny)
library(dplyr)
library(dbplyr)
library(DBI)
library(odbc)
library(shinyjs)
library(DT)
library(digest)


# Define UI for application 

# - User selects some input
# -- db info populates
# - User writes some text
# - User adjusts a slider
# - User clicks "Submit"

# ---Define some global options
fieldsAll <- c('cyl', 'numcars', 'likes')

fieldsMandatory <- c('cyl', 'numcars', 'likes')

labelMandatory <- function(label) {
  tagList(
    label,
    span("*", class = "mandatory_star")
  )
}

appCSS <- 
  ".mandatory_star { color: red; }
   #error { color: red; }
   .shiny-input-container:not(.shiny-input-container-inline) {
  width: 100%; }"

humanTime <- function() format(Sys.time(), "%Y%m%d-%H%M%OS")

db_path <- "Driver={ODBC Driver 17 for SQL Server};Server=tcp:dscoedbserver.database.windows.net,1433;Database=dscoedb;Uid=serveradmin;Pwd={DSCOEdb1234};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"

MY_db <- dbConnect(odbc::odbc(),
                   .connection_string = db_path)

onStop(function() {
  dbDisconnect(MY_db)
  
})
# ---Application
shinyApp(
  ui = fluidPage(
    tags$head(
      tags$style(
        "body{
        min-height: 611px;
        height: auto;
        max-width: 1300px;
        margin: auto;
        border: 4px double grey;
        background-color: white;
        }"
      )
    ),
    shinyjs::useShinyjs(), #allows conditional submit button
    shinyjs::inlineCSS(appCSS), #applys our CSS from the global options
    titlePanel("DSCOE DB App"),
    
    sidebarLayout(
      
      sidebarPanel(
        div(
          id = "form",
          
          selectizeInput("cyl", labelMandatory("Select Favorite Cylinder"), choices = 
                        c("", tbl(MY_db, "new_tbl") %>% select("cyl") %>% distinct() %>%
                                  arrange(.by_group = TRUE) %>% collect())),
          
          p(style="font-size:20px ; color: black ", id = "car_info", "Available HP and Displacement:"),
          tableOutput("hp_info"),
          actionButton("submit", "Submit", class = "btn-primary"), 
          p(style="font-size:16px ; color: red ", id = "info_text", "Cannot submit until all mandatory fields are
            filled."),
          shinyjs::hidden(
            span(id = "submit_msg", "Submitting..."),
            div(id = "error",
                div(br(), tags$b("Error: "), span(id = "error_msg"))
            )
          )
        )
      ),
      
      mainPanel(
        tabsetPanel(id = "inTabset",
          
          tabPanel(title="Info Input Tab", value="infoTab",
                   br(),
                   textAreaInput("likes", labelMandatory("What I Like About These Cars"), width='100%', rows='4'),
                   hr(),
                   br(),
                   div(style="display: inline-block;width: 50%;", sliderInput("numcars", "I have Owned This Many Cars:", 
                                                                              min = 0, max = 5, value = 0)),
                   hr()
                   ) 
        )
      )
    ),
    
    # add a "Thank you" message that will get shown, and add a button to allow the user to submit another response
    shinyjs::hidden(
      div(
        id = "thankyou_msg",
        h3("Thanks, your input was submitted successfully!"),
        actionLink("submit_another", "Submit another", style="display: inline-block; font-size:30px ; width: 50% ; height: 35px; color: black; text-decoration: underline ;")
      )
    )
    
  ),
  
  server = function(input, output, session) {
 
    # Displays options based on selection of cylinder
    output$hp_info <- renderTable({
      #MY_db <- dbConnect(odbc::odbc(),  .connection_string = db_path)
      tbl(MY_db, "new_tbl") %>% filter(cyl == local(input$cyl) ) %>% 
        select(cyl, hp, disp) %>% 
        rename(Cylinders=cyl, HP=hp, Displacement=disp) %>% distinct() %>% collect()
    })
    
    observe({
      # check if all mandatory fields have a value
      mandatoryFilled <-
        vapply(fieldsMandatory,
               function(x) {
                 !is.null(input[[x]]) && input[[x]] != ""
               },
               logical(1))
      mandatoryFilled <- all(mandatoryFilled)
      
      # enable/disable the submit button
      shinyjs::toggleState(id = "submit", condition = mandatoryFilled)
    })
    
    # save each user's input 
    formData <- reactive({
      data <- sapply(fieldsAll, function(x) input[[x]])
      MY_db <- dbConnect(odbc::odbc(),  .connection_string = db_path)
      data <- c(data, timestamp = humanTime())
      data <- as.data.frame(t(data))
      data
    })
    
    # Action to take when submit button is pressed:
    # When the "submit" button is pressed, we want to: disable the button from being pressed again,
    # show the "Submitting." message, and hide any previous errors. We want to reverse these 
    # actions when saving the data is finished. If an error occurs while saving the data, 
    # we want to show the error message.
    observeEvent(input$submit, {
      shinyjs::disable("submit")
      shinyjs::show("submit_msg")
      shinyjs::hide("error")
      
      tryCatch({
        MY_db <- dbConnect(odbc::odbc(),  .connection_string = db_path)
        dbWriteTable(conn = MY_db, name = "app_tbl", value = formData(), append= TRUE, skip=1) 
        dbDisconnect(MY_db)
        shinyjs::reset("form")
        shinyjs::hide("form")
        shinyjs::show("thankyou_msg")
      },
      error = function(err) {
        shinyjs::html("error_msg", err$message)
        shinyjs::show(id = "error", anim = TRUE, animType = "fade")
      },
      finally = {
        shinyjs::enable("submit")
        shinyjs::hide("submit_msg")
      })
    })
    
    # hide the thank you message and reset the form when submit another is clicked
    observeEvent(input$submit_another, {
      shinyjs::show("form")
      shinyjs::hide("thankyou_msg")
      updateTabsetPanel(session, "inTabset", selected="infoTab")
      updateTextAreaInput(session, "likes", value = "")
      updateSliderInput(session, "numcars", value = 0)
    })
    
   # Automatically stop Shiny app when close browser tab
    session$onSessionEnded(stopApp)  
  }
)
