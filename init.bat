@ECHO OFF
setlocal enableextensions enabledelayedexpansion

set PROJECT_HOME=%~dp0
set DEMO=CRC Quick Loan Bank Demo
set AUTHORS=Duncan Doyle, Dana Gutride, Marcos Entenza Garcia, Eric D. Schabell
set PROJECT="git@gitlab.com:redhatdemocentral/crc-quick-loan-bank-demo.git"
set SRC_DIR=%PROJECT_HOME%\installs
set PRJ_DIR=%PROJECT_HOME%\projects
set SUP_DIR=%PROJECT_HOME%\support
set OC_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/"

REM Adjust these variables to point to an OCP instance.
set OPENSHIFT_USER=developer
set OPENSHIFT_PWD=developer
set HOST_IP=api.crc.testing   # set with OCP instance hostname or IP.
set HOST_APPS=apps-crc.testing
set HOST_PORT=6443
set OCP_APP=quick-loan-bank
set OCP_PRJ=appdev-in-cloud

set KIE_ADMIN_USER=erics
set KIE_ADMIN_PWD=redhatdm1!
set PV_CAPACITY=1Gi
set VERSION=77

REM Qlb project details.
set PRJ_ID=loan-application
set PRJ_REPO="https://github.com/jbossdemocentral/rhdm7-qlb-loan-demo-repo.git"

REM waiting max 5 min various container functions to startup.
set DELAY=300   

REM import container functions.
call support\container-functions.bat

REM wipe screen.
cls

echo.
echo ###################################################################
echo ##                                                               ##   
echo ##  Setting up the %DEMO%   ##
echo ##                                                               ##
echo ##                                                               ##   
echo ##  ####  #   # ####  #   #        #### #      ###  #   # ####   ##
echo ##  #   # #   # #   # ## ##   #   #     #     #   # #   # #   #  ##"
echo ##  ####  ##### #   # # # #  ###  #     #     #   # #   # #   #  ##"
echo ##  # #   #   # #   # #   #   #   #     #     #   # #   # #   #  ##"
echo ##  #  #  #   # ####  #   #        #### #####  ###   ###  ####   ##"
echo ##                                                               ##   
echo ##  brought to you by,                                           ##   
echo ##                                                               ##
echo ##  %AUTHORS%      ##
echo ##                                                               ##
echo ##  %PROJECT%  ##
echo ##                                                               ##   
echo ###################################################################
echo.

REM Validate OpenShift
set argTotal=0

for %%i in (%*) do set /A argTotal+=1

if %argTotal% EQU 1 (

    call :validateIP %1 valid_ip

	if !valid_ip! EQU 0 (
	    echo OpenShift host given is a valid IP...
	    set HOST_IP=%1
		echo.
		echo Proceeding with OpenShift host: !HOST_IP!...
	) else (
		echo Please provide a valid IP that points to an OpenShift installation...
		echo.
    GOTO :printDocs
	)

)

if %argTotal% GTR 1 (
    GOTO :printDocs
)

if %argTotal% EQU 0 (
	if [%HOST_IP%] == [] (
		GOTO :printDocs
	)

	echo.
	echo Assuming you set a valid host, so proceeding with: %HOST_IP%
	echo.
)

REM make some checks first before proceeding.	
call where oc version --client >nul 2>&1
if  %ERRORLEVEL% NEQ 0 (
	echo OpenShift command line tooling is required but not installed yet... download here: %OC_URL%
	echo.
	GOTO :EOF
)

echo OpenShift commandline tooling is installed
echo.
echo Logging in to OpenShift as %OPENSHIFT_USER%
echo.
call oc login %HOST_IP%:%HOST_PORT% --password="%OPENSHIFT_PWD%" --username="%OPENSHIFT_USER%"

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc login' command!
	echo.
	GOTO :EOF
)

echo.
echo Check for availability of correct version of Red Hat Decision Manager Authoring template
echo.
call oc get templates -n openshift rhdm%VERSION%-authoring 

if not %ERRORLEVEL% == 0 (
	echo.
	echo Error occurred during 'oc get template rhdm-authoring' command!
	echo.
	echo Your container platform is mising this tempalte versoin in your catalog: rhdm%VERSION%-authoring
	echo Make sure you are using the correct version of CodeReady Containers as listed in project Readme file
	echo.
	GOTO :EOF
)

echo.
echo Creating a new project
echo.
call oc new-project %OCP_PRJ%

echo.
echo Setting up a secrets and service accounts
echo.
call oc process -f support/app-secret-template.yaml -p SECRET_NAME=decisioncentral-app-secret | call oc create -f -
call oc process -f support/app-secret-template.yaml -p SECRET_NAME=kieserver-app-secret | call oc create -f -

if not "%ERRORLEVEL%" == "0" (
	echo.
	echo Error occurred during 'oc process' command!
	echo.
	GOTO :EOF
)

echo.
echo Setting up secrets link for kieserver user and password
echo.
call oc create secret generic rhpam-credentials --from-literal=KIE_ADMIN_USER=%KIE_ADMIN_USER% --from-literal=KIE_ADMIN_PWD=%KIE_ADMIN_PWD%

if not "%ERRORLEVEL%" == "0" (
  echo.
  echo Error occurred during 'oc secrets' creating kieserver user and password!
  echo.
  GOTO :EOF
)

echo.
echo Processing to setup KIE-Server with CORS support
echo.
call oc process -f %SUP_DIR%/rhdm%VERSION%-kieserver-cors.yaml -p DOCKERFILE_REPOSITORY="https://gitlab.com/redhatdemocentral/crc-quick-loan-bank-demo.git" -p DOCKERFILE_REF="master" -p DOCKERFILE_CONTEXT=%SUP_DIR%/rhdm%VERSION%-kieserver-cors | call oc create -f -

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc process' cors kie-server command!
  echo.
  GOTO :EOF
)

echo.
echo Creating a new application using CRC catalog image
echo.
call oc new-app --template=rhdm%VERSION%-authoring -p APPLICATION_NAME="%OCP_APP%" -p CREDENTIALS_SECRET="rhpam-credentials" -p DECISION_CENTRAL_HTTPS_SECRET="decisioncentral-app-secret" -p KIE_SERVER_HTTPS_SECRET="kieserver-app-secret" -p MAVEN_REPO_USERNAME="%KIE_ADMIN_USER%" -p MAVEN_REPO_PASSWORD="%KIE_ADMIN_PWD%" -p DECISION_CENTRAL_VOLUME_CAPACITY="%PV_CAPACITY%"

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc new-app' command!
	echo.
	GOTO :EOF
)

echo.
echo Setting up old openshift controller strategy
echo.
REM Disable the OpenShift Startup Strategy and revert to the old Controller Strategy
call oc set env dc/%OCP_APP%-rhdmcentr KIE_WORKBENCH_CONTROLLER_OPENSHIFT_ENABLED=false
call oc set env dc/%OCP_APP%-kieserver KIE_SERVER_STARTUP_STRATEGY=ControllerBasedStartupStrategy KIE_SERVER_CONTROLLER_USER=%KIE_ADMIN_USER% KIE_SERVER_CONTROLLER_PWD=%KIE_ADMIN_PWD% KIE_SERVER_CONTROLLER_SERVICE=%OCP_APP%-rhdmcentr KIE_SERVER_CONTROLLER_PROTOCOL=ws  KIE_SERVER_ROUTE_NAME=insecure-%OCP_APP%-kieserver

echo.
echo Patch the KIE-Server name to use CORS support
echo.
call oc patch dc/%OCP_APP%-kieserver --type='json' -p="[{'op': 'replace', 'path': '/spec/triggers/0/imageChangeParams/from/name', 'value': 'rhdm%VERSION%-kieserver-cors:latest'}]"

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc patch' kie-server name cors support command!
	echo.
	GOTO :EOF
)

echo.
echo Patch the KIE-Server namespace to use CORS support
echo.
call oc patch dc/%OCP_APP%-kieserver --type='json' -p="[{'op': 'replace', 'path': '/spec/triggers/0/imageChangeParams/from/namespace', 'value': '%OCP_PRJ%'}]"

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc patch' kie-server namespace cors support command!
	echo.
	GOTO :EOF
)

echo Waiting until container is ready...
echo.
CALL :containerReady CONTAINER_READY

if %CONTAINER_READY% (
	echo.
	echo The container has started
	echo.
) else (
	echo Exiting now with CodeReady Container started, but not sure if
	echo authoring environment is ready and did not install the demo project.
	echo.
	GOTO :EOF
)

echo Creating a space for the project import
echo.
CALL :createProjectSpace CREATE_SPACE

if %CREATE_SPACE% (
  echo Creation of new space for project import started
  echo.
) else (
  echo Exiting now with CodeReady Container started, but not sure if
  echo authoring environment is ready and did not install the demo project.
	echo.
	GOTO :EOF
)

echo Validating new project space creation
echo.
CALL :validateProjectSpace VALIDATED_SPACE

if %VALIDATED_SPACE% (
	echo Creation of space successfully validated
	echo.
) else ( 
	echo Exiting now with CodeReady Container started, autorhing environment
	echo is ready, but unable to import the demo project.
	echo.
	GOTO :EOF
)

echo Checking if project already exists, otherwise add it
echo.
CALL :projectExists PROJECT_EXISTS

if %PROJECT_EXISTS% (
	echo Demo project already exists
	echo.
) else (
	echo Project does not exist, importing in to container
	echo.
	
	CALL :projectImported PROJECT_IMPORTED

	if %PROJECT_IMPORTED% (
		echo Imported project successfully
		echo.
	) else (
	  echo Exiting now with Code ReadyContainer started, authoring environment
	  echo is ready, but unable to import the demo project.
	  echo.
		GOTO :EOF
	)
)

echo.
echo Creating a new application using CRC Node.js catalog image
echo.
call oc new-app "nodejs:12~https://gitlab.com/redhatdemocentral/crc-%OCP_APP%-demo.git" --name="qlb-client-application" --context-dir="%PRJ_DIR%\application-ui" -e NODE_ENV="development" --build-env NODE_ENV="development"

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc new-app' node.js command!
	echo.
	GOTO :EOF
)

echo.
echo Creating config-map for client application
echo. 
call oc create configmap qlb-client-application-config-map --from-file="%PRJ_DIR%\application-ui\config\config.js"

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc create' config-map command!
	echo.
	GOTO :EOF
)

echo.
echo Attaching config-map as volume to client application
echo.
call oc patch deployment/qlb-client-application -p '{"spec":{"template":{"spec":{"volumes":[{"name": "volume-qlb-client-app-1", "configMap": {"name": "qlb-client-application-config-map", "defaultMode": 420}}]}}}}' 

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc patch' client volumes command!
	echo.
	GOTO :EOF
)

call oc patch deployment/qlb-client-application -p '{"spec":{"template":{"spec":{"containers":[{"name": "qlb-client-application", "volumeMounts":[{"name": "volume-qlb-client-app-1","mountPath":"/opt/app-root/src/config"}]}]}}}}'

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc patch' client containers command!
	echo.
	GOTO :EOF
)

echo.
echo Patch the service to set targetPort to 3000
echo.
call oc patch svc/qlb-client-application --type='json' -p="[{'op': 'replace', 'path': '/spec/ports/0/targetPort', 'value': 3000}]"

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc patch' client targetPort command!
	echo.
	GOTO :EOF
)

echo.
echo Expose the client application service (route)
echo.
call oc expose svc/qlb-client-application

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc expose' client route command!
	echo.
	GOTO :EOF
)

echo.
echo ========================================================================
echo =                                                                      =
echo =  Log in to Red Hat Decision Manager to exploring decision logic      =
echo =  development at:                                                     =
echo =                                                                      =
echo =   https://%OCP_APP%-rhdmcentr-%OCP_PRJ%.%HOST_APPS%     =
echo =                                                                      =
echo =    Log in: [ u:erics / p:redhatdm1! ]                                =
echo =                                                                      =
echo =  See README.md for general details to run the various demo cases.    =
echo =                                                                      =
echo ========================================================================
echo.

GOTO :EOF
      

:validateIP ipAddress [returnVariable]

    setlocal 

    set "_return=1"

    echo %~1^| findstr /b /e /r "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*" >nul

    if not errorlevel 1 for /f "tokens=1-4 delims=." %%a in ("%~1") do (
        if %%a gtr 0 if %%a lss 255 if %%b leq 255 if %%c leq 255 if %%d gtr 0 if %%d leq 254 set "_return=0"
    )

:endValidateIP

    endlocal & ( if not "%~2"=="" set "%~2=%_return%" ) & exit /b %_return%
	
:printDocs

  echo The default option is to run this using CodeReady Containers, an OpenShifContainer
  echo Platform for your local machine. This host has been set by default in the variables at
	echo the top of this script. You can modify if needed for your own host and ports by mofifying
	echo these variables:
	echo.
	echo     HOST_IP=api.crc.testing
  echo     HOST_PORT=6443
	echo.
	echo It's also possible to install this project on a personal CodeReady Containers installation, just point
  echo this installer at your installation by passing an IP address of the hosting cluster:
	echo.
	echo    $ init.bat IP
	echo.
	echo IP could look like: 192.168.99.100
	echo.
	echo Both methodes are validated by the install scripts.
	echo.

