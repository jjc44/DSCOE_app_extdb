library(shiny)
library(shinydashboard)
library(shinyjs)
library(ggplot2)
library(dplyr)
library(dbplyr)
library(DBI)
library(odbc)
library(rmarkdown)

db_path <- "Driver={ODBC Driver 17 for SQL Server};Server=tcp:dscoedbserver.database.windows.net,1433;Database=dscoedb;Uid=serveradmin;Pwd={DSCOEdb1234};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"

MY_db <- dbConnect(odbc::odbc(),
                   .connection_string = db_path)

ui <- dashboardPage(
  dashboardHeader(title = "DSCOE Dashboard", 
                  dropdownMenuOutput("notif"),
                  dropdownMenuOutput("task")
                  ),
  dashboardSidebar(

    sidebarMenu(
      menuItem("Dashboard", tabName = "dashboard", icon = icon("dashboard"))
    )
  ),
  dashboardBody(
    tags$head(
      tags$style(
        "body{
        min-height: 611px;
        height: auto;
        max-width: 1200px;
        margin: auto;
        background-color: slategrey;
        }"
      )
      ),

    tabItems(
      # Tab content
      tabItem(tabName = "dashboard",
              selectizeInput("cyl", "Select Cylinders", 
                             selected = "", 
                             choices = tbl(MY_db, "app_tbl") %>% select("cyl") %>% distinct() %>%
                                   arrange(.by_group = TRUE) %>% collect()
                             ),
              fluidRow(
              box(height = 650, width = 8, plotOutput("cyl_bar", width = "100%", height = "600px")
              ),
              box(height = 650, width = 4, plotOutput("numcars_bar", width = "100%", height = "400px")
              )
              ),
              uiOutput('select_cyl'),
              downloadButton("submit_some", " Generate Report for Selected Cylinders"),
              br(), br(),
              downloadButton("submit_all", " Generate Report for ALL Cylinders")
      )
    )
  )
)

server <-function(input, output, session) {

  # Notification for new submissions in last 12 hours 
  output$notif <- renderMenu({
    MY_db <- dbConnect(odbc::odbc(),  .connection_string = db_path)
    Cyltime <- tbl(MY_db, "app_tbl") %>% 
      collect() %>% 
      filter(as.numeric(difftime(as.POSIXct(timestamp,format="%Y%m%d-%H%M%OS"), 
                                 as.POSIXct(Sys.time(),format="%Y%m%d-%H%M%OS"), 
                                 units = "hours")) > -12)
    dropdownMenu(type = "notifications", badgeStatus = "warning",
                notificationItem(
                 text = paste(length(Cyltime$timestamp), "new submissions in last 12 hrs"),
                 icon("file"),
                 status = "success"
               )
    )
  })

  output$task <- renderMenu({ 
    MY_db <- dbConnect(odbc::odbc(),  .connection_string = db_path)

    num <- length(unlist(tbl(MY_db, "app_tbl") %>% select(cyl) %>% collect()))
    dropdownMenu(type = "notifications", badgeStatus = "success",
                 notificationItem(text = paste(num, "Total Submissions"),
                                  status = "success")   
    )
  })
  
  output$cyl_bar <- renderPlot({ 
    MY_db <- dbConnect(odbc::odbc(),  .connection_string = db_path)
    
    # Cylinder plot data (HP vs Displacement)
    plot_data <- tbl(MY_db, "new_tbl") %>% filter(cyl == local(input$cyl) ) %>% 
      select(hp, disp) %>% 
      rename(HP=hp, Displacement=disp) %>% collect()

    # Plot to show HP vs Displacement for this cylinder
    ggplot(data= plot_data, aes(x=HP, y=Displacement)) + 
      geom_point() + labs(title="Power and Engine Displacement") + 
      theme_bw() + theme(panel.border = element_blank(), 
                         plot.title = element_text(hjust = 0.5))
  })
  
  output$numcars_bar <- renderPlot({ 
    MY_db <- dbConnect(odbc::odbc(),  .connection_string = db_path)
    
    # Count plot data 
    plot_data1 <- tbl(MY_db, "app_tbl") %>% filter(cyl == local(input$cyl) ) %>% 
      select(cyl, numcars) %>% collect()
    
    # Plot to show Number Cars of Owned
    ggplot(data= plot_data1, aes(x=cyl, y=numcars)) + 
      geom_boxplot() + geom_point() + labs(title="Number Cars of Owned", y="Number of Cars Owned") + 
      theme_bw() + theme(axis.text.x = element_blank(),
                         panel.border = element_blank(), 
                         plot.title = element_text(hjust = 0.5))
  })
  

  output$select_cyl <- renderUI({
    selectInput("select_cyl", label = "Select Cylinders to Print Reports",
              choices = tbl(MY_db, "app_tbl") %>%  
                select("cyl") %>% distinct() %>% collect(),
              multiple = TRUE, selectize = TRUE, width = "20%")
  })
  
  
  output$submit_some <- downloadHandler(
    filename = "DSCOEreport.pdf",
    content = function(file) {
      tempReport <- file.path(tempdir(), "DSCOEreport.Rmd")
      file.copy("DSCOEreport.Rmd", tempReport, overwrite = TRUE)

      params <- list(cyl = input$select_cyl)

      rmarkdown::render(tempReport, 
             output_file = file,
             params = params,
             envir = new.env(parent = globalenv())
      )
    }
  )
  
  output$submit_all <- downloadHandler(
    filename = "DSCOEreport.pdf",
    content = function(file) {
      tempReport <- file.path(tempdir(), "DSCOEreport.Rmd")
      file.copy("DSCOEreport.Rmd", tempReport, overwrite = TRUE)
      
      params <- list(cyl = tbl(MY_db, "app_tbl") %>%  
                       select("cyl") %>% distinct() %>% collect())
      
      rmarkdown::render(tempReport, 
                        output_file = file,
                        params = params,
                        envir = new.env(parent = globalenv())
      )
    }
  )

  # Automatically stop Shiny app when close browser tab
  session$onSessionEnded(stopApp)
  }

shinyApp(ui, server)