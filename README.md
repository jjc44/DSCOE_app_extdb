# Docker Deployment of a Shiny App, Dashboard, and SQL Database to Azure

## Background

This tutorial will take the previously developed shiny app, dash, and database and build a docker container to efficiently host the app on Azure via App Services. You can sign up for a free Azure Dev account that gives you a chunk of free access that is plenty to follow this tutorial or your own small project.  I used GitHub and DockerHub in the process of this tutorial, as these are very beneficial to versioning and development of your workflow. 

The app code and project files are available in this repo [linked right here](https://github.com/jjc44/DSCOE_app_extdb), so I won't be reproducing the app code in this post.

Start by [installing Docker and following the additional configuration steps](https://docs.docker.com/get-docker/).  Create a DockerHub account as well.

<br/>

## 1. Basic Development Progression

This is probably not an approved DevOps solution, but this is how I worked through the process of taking a working local application to a cloud-served application.

- Develop a working local project (app, dash, db, reports) and push to GitHub
- Dockerize the local project and get it running locally, push the image to DockerHub
- Configure a Docker image to run the project on a server and push to DockerHub (or Azure Container Registry)
- Deploy the image to a cloud server (Azure App Service)

<br/>

## 2. Developing a Working Project

Since the development of a working local project was written up previously [here](https://dscoe.org/post/82/), I will assume you have a working shiny project.  This project has an app that takes input from a user and stores the info a SQLite database, a dashboard that shows which input exists in the database and allows for downloading reports, using an associated rmarkdown template report.  Use the udpated project code (which includes connection to the remote SQL database, discussed later) from my [github repo](https://github.com/jjc44/DSCOE_app_extdb), which you can pull down and get going.

If you already are using Git on your projects, good.  If not and if you are developing your own Shiny web app, you can start now. Install or update git on your machine by following steps [here](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git).  Then sign up for an account on GitHub [here](https://github.com/join).  

Follow these [instructions](https://gist.github.com/mindplace/b4b094157d7a3be6afd2c96370d39fad) to initialize git, set up a new repo, connect your local project to GitHub, and then commit and push your changes. 

As you make changes to your project throughout the dev process, you can commit changes and push to GitHub to keep your repo up to date. Additionally, once you have your app hosted, you can link the app service to your github repository, such that your app rebuilds its image each time you make changes to the source code.  The helps automate the process of updating your app. 

#### A note on this Docker deplyment design:  

The general framework for the Dockerized project could take the form of multiple docker containers, one for the app, one for the dashboard, and one for the database.  However, from reading up on this, I thought I could do it all from a single container and utilize Docker's volume persistant storage framework to hold the database.  This approach ended up not working!  This approach worked great in a local environment, notably persisting the SQLite database in a Docker volume mapped to the container.  However, the way Azure manages Docker volumes is not compatible.  It turned out there there were multiple open issues with Azure's persisted storage options and SQLite files which could not be overcome. 

This was a process of discovery for me, which included a lot of hours perfecting Dockerfiles and config files locally, that could not work on Azure's remote server framework.  Lesson learned.  

In the end, I took the SQLite database and converted to an MS SQL Server database hosted on Azure so that I could persist the data and have access to it outside of a container. This had the added benefit of being able to develop the Docker image on my local machine and use the same database connection that would be used when the container is deployed on Azure. Additionally, when I had been working with the persistant storage volume, I had to configure SSH to the container so that I could admin the database.  With a separate SQL database, I would not have to SSH to the app container at all and could just use my local R installation to admin the database. 

<br/>

## 3. Containerize Your App 

Here are few great references for getting started with Docker and R/Shiny:

- https://www.rocker-project.org/  
- https://colinfay.me/docker-r-reproducibility/
- https://chapmandu2.github.io/post/2019/05/19/dockerizing-your-shiny-app/
- https://juanitorduz.github.io/dockerize-a-shinyapp/

I ended up taking a slightly different approach that those shown, but incorporated methods from all three of the above and a bunch of other unrelated projects.  The general appraoch was to start with a stable Docker image from DockerHub.  The rocker project has a bunch of good R and shiny images.  I chose to start from the rocker/verse image for a number of reasons.  First, the image is built on Debian 10 and comes with a stable version of RStudio, RStudio-server, Shiny-server, the Tidyverse, and TinyTex installed.  TinyTex was needed for my report generation, so that was a bonus. Second, it allows you to set the version of R and all package downloads are then matched to that version of R. This way, your packages in the container are not going to get updated without you knowing about it.  Although I did not need RStudio in the image, I found that the RStudio install solves many problems with pandoc and LaTeX packages that were a pain without RStudio installed.    

All of the instructions to create your container are contained in the Dockerfile, which is just a text file with commands for your installs, copying files, granting permissions, etc on the container you are creating. The commands in your docker file are being executed in bash on whatever your image OS is, in my case Debian.  A good resource to understand Docker is the [Docker documentation](https://docs.docker.com/get-started/overview/), go figure.  To start, my Dockerfile looked like this:
        
        FROM rocker/verse:3.6.0
        
        # add shiny server
        RUN export ADD=shiny && bash /etc/cont-init.d/add
        
        ###
        #install linux dependencies
        
        RUN apt-get update -qq && apt-get -y --no-install-recommends install \
          curl \
          && install2.r --error \
            --deps TRUE \
            shinydashboard 


<br/>    
From the base Dockerfile, I then added components that I would need to run my application in a container. 

Start with your app.  All the R packages used in the app need to be added to the Dockerfile. I did this using ```remotes::install_version()``` so that I could control which version got installed. I took all the packages that I needed to use in the app, dashboard, and rmarkdown file used to generate the pdf reports and added them to my Dockerfile like this:

        #install R packages
        RUN R -e "tinytex::tlmgr_install(c('tools', 'booktabs', 'multirow', 'setspace', 'wrapfig', 'colortbl', 'tabu', 'varwidth', 'threeparttable', 'threeparttablex', 'environ', 'trimspaces', 'ulem', 'makecell', 'xcolor')); \
          remotes::install_version('dbplyr', version = '1.4.0', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('DBI', version = '1.1.0', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('odbc', version = '1.1.6', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('shinyjs', version = '1.0', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('DT', version = '0.13', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('kableExtra', version = '1.1.0', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('gridExtra', version = '2.3', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('digest', version = '0.6.25', repos = 'http://cran.us.r-project.org');"

<br/>    
Note that the first line of R code in this command installs some additional LaTeX packages needed in my pdf report generation.  Without adding them to the Dockerfile results in about a 6 minute download time for the first report that the dashboard generates, since these packages have to be updated by TinyTex in the course of knitting the Rmarkdown document. 

### Adding Persistent Storage

According to the [docker page on storage](https://docs.docker.com/storage/),

>>If you mount an empty volume into a directory in the container in which files or directories exist, these files or directories are propagated (copied) into the volume.  

This was what I initially intended for my SQLite database because the first time I run the container, the database will be populated in the volume, then with each use of the app, the database will be updated and persisted.  I can then back up the database as need be through SSH to the container.  

But this didn't work.  I discovered many open issues with SQLite and containerized webapps with Azure.  Although use of a SQLite db is common in app developement, production apps are less likely to use SQLite, plus Microsoft would rather you use their databse services anyway.  All that to say that Azure is unlikely to support SQLite files in volumes at any point in the future. 

So I audibled and went to an MS SQL database.  Since I had an Azure account, I created an empty SQL Server database as an Azure resource. Azure makes a GUI interface so that you can easily manage the database.  Once I had the empty database, I could use R to connect and manipulate it as needed. 

I followed this [configuration guide](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-design-first-database) and configured the firewall settings to allow connections from both my local computer IP as well as the "Allow Azure Services and Resources to Access This Server" option, since my web app is an Azure Service. 

In order to connect to the SQL database, I would need additional libraries added to my Docker image. Since I use dbplyr to access the database in my app and dash, I would need the odbc package, which connects to many commercial databases via the open database connectivity protocol.  My image is built on Debian, so I followed the [odbc repo](https://github.com/r-dbi/odbc#odbc) instructions to download and install UnixODBC and the Microsoft drivers on the image as well as my Mac for local development purposes.  To do this on the image, I added the install bash commands to a RUN layer in my Dockerfile:

        # install UnixODBC - Required for all databases
        RUN apt-get -y --no-install-recommends install \
          unixodbc \
          unixodbc-dev \
          gnupg \
          # install microsoft sql drivers
          && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
          && curl https://packages.microsoft.com/config/debian/10/prod.list > /etc/apt/sources.list.d/mssql-release.list \
          && apt-get install apt-transport-https \
          && apt-get update \
          && ACCEPT_EULA=Y apt-get install msodbcsql17 

<br/>    
While I am on the subject of the database change, I'll quickly show how easy it was to transition from SQLite to a different database.  SQLite databases are flat files that can be located pretty much anywhere in file storage.  In my original project, I was accessing the SQLite database like this:

        library(RSQLite)
        
        db_path <- '/Users/mh302/DSCOE_app/data/MY_db.sqlite'
        MY_db <- dbConnect(SQLite(), db_path)

<br/>    
But now I would use odbc to access the SQL database hosted on Azure. In my databse resource dashboard on Azure, I could pull the connection string to the database, using this instead of the local file path that I had used for the SQLite connection.  Connecting to the Azure db and put some toy data in the new database that matched my project was very easy.  note that I had to check which drivers were installed with ```odbc::odbcListDrivers()``` and then put these drivers in the "Driver={};" portion of the connection string. 

        library(DBI)
        library(dbplyr)
        library(dplyr)
        library(odbc)
        
        #Install from https://github.com/r-dbi/odbc#odbc
         
        # check that drivers are installed
        odbc::odbcListDrivers()
        
        # copy connnection string from azure db resource and paste below,
        # then change the Driver to match the "name" of the driver the above command produced in your console
        con <- dbConnect(odbc::odbc(), 
                         .connection_string = "Driver={ODBC Driver 17 for SQL Server};
                         Server=tcp:dscoedbserver.database.windows.net,1433;
                         Database=dscoedb;Uid=serveradmin;Pwd={DSCOEdb1234};
                         Encrypt=yes;
                         TrustServerCertificate=no;
                         Connection Timeout=30;"
                         )
        
        # check what tables already exist in the db
        dbListTables(con)
        
        # add a new table using the mtcars dataframe from R
        dbWriteTable(con, "new_tbl", mtcars, overwrite=TRUE)
        
        # View the first few records from each table (collect() actually executes the query)
        tbl(con, "new_tbl") %>% head(n=12) %>% collect() 
        
        # Write some field names to an empty dataframe
        df <- data.frame('cyl'=integer(), 'numcars'=integer(), 'likes'=character(), 'timestamp'=character())
        
        # Create a new table from the dataframe
        dbWriteTable(con, "app_tbl", df, overwrite=TRUE)

<br/>    
Back to the Dockerfile.  

Next, I needed to copy over my local app files to the Docker image. My local project directory looked like this:

<pre>
DSCOE_app_extdb
.
├── Dockerfile
├── README.md
├── dash
│    ├── DSCOEreport.Rmd
│    └── app.R
├── dscoe_app
│    └── app.R
└── shiny-server.conf

</pre>

Copying files and folders is straightforward in the Dockerfile:

        COPY ./shiny-server.conf /etc/shiny-server/shiny-server.conf
        COPY ./dscoe_app /home/rstudio/ShinyApps/dscoe_app/
        COPY ./dash /home/rstudio/ShinyApps/dash/

<br/>    
The way this image is configured, the apps run out of the ShinyApps directory mapped to /home in the container.  The shiny-server.conf file is also copied into the proper directory so that shiny can use any changes you need to how the server is configured.  In my case, I needed to add non-shiny users with the addition of :HOME_USER: environmental variable, as well as extend the keep-alive timeout, which I needed for dev purposes due to missing LaTeX packages on knitting. You can see the specifics in my GitHub repo if need be.

The rocker Docker images are great and well documented - their default user is rstudio and default password is rstudio, which they require you to change in your ```docker run``` command or else it throws an error.  You can do this easily by adding ```-e PASSWORD=<your password>``` to your ```run``` command in a local environment, but you wouldn't want to do this in production.  Because this is a toy app, I took the easy way out and just added the PASSWORD environmental variable in my Dockerfile so that I wouldn't have to deal with it.  In production, you would likely choose [one of these options](https://stackoverflow.com/questions/22651647/docker-and-securing-passwords) to better manage the app security. 

To finish off the Dockerfile, I needed to expose the ports that rstudio and shiny broadcast from the container, as well as allow user permission to the app directories, so I added these to the end of my Dockerfile.  The completed Dockerfile now looks like this:

        FROM rocker/verse:3.6.0
        
        # add shiny server
        RUN export ADD=shiny && bash /etc/cont-init.d/add
        
        ###
        #install linux dependencies
        
        RUN apt-get update -qq && apt-get -y --no-install-recommends install \
          curl \
          && install2.r --error \
            --deps TRUE \
            shinydashboard 
        
        
        ###
        #install R packages
        
        RUN R -e "tinytex::tlmgr_install(c('tools', 'booktabs', 'multirow', 'setspace', 'wrapfig', 'colortbl', 'tabu', 'varwidth', 'threeparttable', 'threeparttablex', 'environ', 'trimspaces', 'ulem', 'makecell', 'xcolor')); \
          remotes::install_version('dbplyr', version = '1.4.0', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('DBI', version = '1.1.0', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('odbc', version = '1.1.6', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('shinyjs', version = '1.0', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('DT', version = '0.13', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('kableExtra', version = '1.1.0', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('gridExtra', version = '2.3', repos = 'http://cran.us.r-project.org'); \
          remotes::install_version('digest', version = '0.6.25', repos = 'http://cran.us.r-project.org');"
        
        ###
        # install UnixODBC - Required for all databases
        RUN apt-get -y --no-install-recommends install \
          unixodbc \
          unixodbc-dev \
          gnupg \
          # install microsoft sql drivers
          && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
          && curl https://packages.microsoft.com/config/debian/10/prod.list > /etc/apt/sources.list.d/mssql-release.list \
          && apt-get install apt-transport-https \
          && apt-get update \
          && ACCEPT_EULA=Y apt-get install msodbcsql17 
        
        ###
        # copy over my project files
        COPY ./shiny-server.conf /etc/shiny-server/shiny-server.conf
        COPY ./dscoe_app /home/rstudio/ShinyApps/dscoe_app/
        COPY ./dash /home/rstudio/ShinyApps/dash/
        
        # change password from rstudio
        ENV PASSWORD=DSCOEapp1234
        
        # select ports (8787 is for RStudio, not available in the final Azure Web App, but useful locally)
        EXPOSE 3838 8787
        
        # allow permission
        RUN sudo chown -hR rstudio:rstudio /home/rstudio/ShinyApps

<br/>   

With a Dockerfile and my project files, I can now build the image (assuming you have configured Docker already). Open a terminal and get into the app project directory (where your Dockerfile is located) and run ```docker build -t dscoe_app_extdb .``` , where dscoe_app_extdb is my image name (which matches my Github repo and my DockerHub repo, and will also match my Azure App Service resource for simplicity).  Docker will build the image from source, which will take some time, but you can monitor progress in the terminal output.  

Once the image is built, you can run the container for your app, which is just an instance of your image.  In the terminal, run ```docker run --rm -p 8787:8787 -p 3838:3838 -e DISABLE_AUTH=true dscoe_app_extdb```, which runs an instance of your image, exposing port 8787 running rstudio-server on the container and forwarding to port 8787 on your localhost.  Similarly with port 3838 running shiny-server on the container and forwarding to port 3838 on your localhost. 

You can now access your container's rstudio session through localhost:8787.  You can also access the app and dashboard through http://localhost:3838/users/rstudio/dscoe_app/ and http://localhost:3838/users/rstudio/dash/ respectively.  

Having RStudio running on the container and available through a browser was SUPER handy during development, as I could play around with Linux and R libraries without having to re-build the image each time.  Once I got the configuration right on a running container, I could just go back and update the Dockerfile, rebuild, and then I was ready to push to Azure Container Registry. 

You can see that the app spins up quickly, is immediately connected to the database hosted on Azure, and has the read and write permissions needed to hit the database. The RStudio session can be used to play around with the app, dash, or rmd files that you copied into the image. Note that any changes you make to the files or container itself are lost when the container is stopped.  This is easily overcome by using Docker volumes, but was not done for this image.  Finally, you can access a bash shell in your container by using ```docker ps``` to identify the container id, then ```docker exec -t -i <container id> /bin/bash``` to run a bash shell.  This was useful to access directories as I was further configuring the image for deployment.  

Now that the image is built and runs well locally, you can push the image to your DockerHub account following [these steps.](https://ropenscilabs.github.io/r-docker-tutorial/04-Dockerhub.html)


## 5. Configure the Docker Image to Run on a Remote Server

A couple of things change when you go from a container that runs well locally to an image that will run on a remote server:

- ports: You have to manually change the ports observed by Azure, either in the portal or azure cli after pushing your docker image.  Also of note, Azure only allows exposure of one port from containerized App Services.  In my case, I would no longer need to use RStudio, so 8787 would not be accessible any longer once deplyed. 
- persistant volumes: You can use the /home directory in your app's file system to persist files across restarts and share them across instances. The /home in your app is provided to enable your container app to access persistent storage.  
- SSH bash shell ability: You have to explicitly add ssh capabilities into your Dockerfile. This configuration doesn't allow external connections to the container. SSH is available only through https://<app-name>.scm.azurewebsites.net and authenticated with the publishing credentials.  


I didn't end up needing to use volumes or the SSH bash shell in my container because I went the SQL database route.  Azure has fairly clear documentation of these things, so I followed their examples to get to success. I will quickly show what needed to change, but point you towards the azure documentation for more information.

- ports (https://docs.microsoft.com/en-us/azure/container-instances/container-instances-volume-azure-files)  
- persistant volumes (https://docs.microsoft.com/en-us/azure/container-instances/container-instances-volume-azure-files)  
- bash shell ability (https://docs.microsoft.com/en-us/azure/app-service/containers/configure-custom-container#enable-ssh)  


## 6. Azure Deployment

I assume you have an Azure account or have signed up for a [free one](https://azure.microsoft.com/en-us/free/).

Since I cannot do a better job explaining the process than Microsoft, I have linked the Azure tutorial I followed [here](https://docs.microsoft.com/en-us/learn/modules/deploy-run-container-app-service/), although I had to do a few extra things to get the app running, listed below.  

- Set up an Azure Container Registry resource (follow the tutorial)

- Push your image to Azure Container Registry

  a). First install the Azure command line interface, shown [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest).  
  
  b). The use the terminal to login to your Azure account with ```az login```.  
  
  c). Then from the terminal within your project directory, send the folder's contents to Azure Container Registry, which uses the Docker file to build the image and store it.  The command for this was ```az acr build --registry dscoe --image dscoe_app_extdb .``` This process takes about 20 minutes.  

- Set up an Azure App Service resource

  a). Follow the tutorial.  Then you need to tell Azure about the port that your custom container uses by using the WEBSITES_PORT app setting. In your terminal, type ```az webapp config appsettings set --resource-group myResourceGroup --name dscoeappdep --settings WEBSITES_PORT=3838```
  
  b). Then allow access to console logs from the container with ```az webapp log config --name dscoeappdep --resource-group myResourceGroup --docker-container-logging filesystem``` and wait about a minute.  Then ```az webapp log tail --name dscoeappdep --resource-group myResourceGroup``` should show the logs.

- Deploy your app on Azure App Service
  
  a). Click on "restart" in the App Service resource to put the changes into play.  
  
  b). Now the app is available through a browser at https://dscoe.azurewebsites.net/users/rstudio/dscoe_app.  This site is publicly available.  If you organization leverages Azure for enterprise services, then there is likely an Active Directory that you can use to control access to your site.  If AD is not available to you, you can also set permissions from the Azure resource itself.  

A final note on continuous deployment from Azure: 

>> Azure App Service supports continuous deployment using webhooks. A webhook is a service offered by Azure Container Registry. Services and applications can subscribe to the webhook to receive notifications about updates to images in the registry. A web app that uses App Service can subscribe to an Azure Container Registry webhook to receive notifications about updates to the image that contains the web app. When the image is updated, and App Service receives a notification, your app automatically restarts the site and pulls the latest version of the image.

Additionally, Container Registry can auto-rebuild your image when your source code changes:

>> You use the tasks feature of Container Registry to rebuild your image whenever its source code changes automatically. You configure a Container Registry task to monitor the GitHub repository that contains your code and trigger a build each time it changes. If the build finishes successfully, Container Registry can store the image in the repository. If your web app is set up for continuous integration in App Service, it receives a notification via the webhook and updates the app.

This allows you to quickly update and redeploy your app on Azure as you continue to develop features.  

