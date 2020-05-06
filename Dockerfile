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

# break the cache here for a rerun following update to the DSCOE_app.R, use --build-arg DATE_VER=20200428 in the build command
#ARG DATE_VER=unknown


COPY ./shiny-server.conf /etc/shiny-server/shiny-server.conf
COPY ./dscoe_app /home/rstudio/ShinyApps/dscoe_app/
COPY ./dash /home/rstudio/ShinyApps/dash/

# change password from rstudio
ENV PASSWORD=DSCOEapp1234

# select ports
EXPOSE 3838 8787

# allow permission
RUN sudo chown -hR rstudio:rstudio /home/rstudio/ShinyApps


