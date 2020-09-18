@ECHO OFF
setlocal enableextensions enabledelayedexpansion

set PROJECT_HOME=%~dp0
set DEMO=Red Hat Decision Manager Install Demo
set AUTHORS=Andrew Block, Eric D. Schabell, Duncan Doyle
set PROJECT=git@gitlab.com:redhatdemocentral/rhcs-rhdm-install-demo.git
set SRC_DIR=%PROJECT_HOME%\installs
set OC_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.3

REM Adjust these variables to point to an OCP instance.
set OPENSHIFT_USER=developer
set OPENSHIFT_PWD=developer
set HOST_IP=api.crc.testing   # set with OCP instance hostname or IP.
set HOST_APPS=apps-crc.testing
set HOST_PORT=6443
set OCP_APP=rhcs-rhdm-install-demo
set OCP_PRJ=appdev-in-cloud

set KIE_ADMIN_USER=erics
set KIE_ADMIN_PWD=redhatdm1!
set PV_CAPACITY=1Gi
set VERSION=74

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
echo ##             %AUTHORS%      ##
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

echo OpenShift commandline tooling is installed...
echo.
echo Logging in to OpenShift as %OPENSHIFT_USER%...
echo.
call oc login %HOST_IP%:%HOST_PORT% --password="%OPENSHIFT_PWD%" --username="%OPENSHIFT_USER%"

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc login' command!
	echo.
	GOTO :EOF
)

echo.
echo Check for availability of correct version of Red Hat Decision Manager Authoring template...
echo.
call oc get templates -n openshift rhdm%VERSION%-authoring 

if not %ERRORLEVEL% == 0 (
	echo.
	echo Error occurred during 'oc get template rhdm-authoring' command!
	echo.
	echo Your container platform is mising this tempalte versoin in your catalog: rhdm%VERSION%-authoring
	echo Make sure you are using the correct version of Code Ready Containers as listed in project Readme file
	echo.
	GOTO :EOF
)

echo.
echo Creating a new project...
echo.
call oc new-project %OCP_PRJ%

echo.
echo Setting up a secrets and service accounts...
echo.
call oc process -f support/app-secret-template.yaml -p SECRET_NAME=decisioncentral-app-secret | oc create -f -
call oc process -f support/app-secret-template.yaml -p SECRET_NAME=kieserver-app-secret | oc create -f -

if not "%ERRORLEVEL%" == "0" (
	echo.
	echo Error occurred during 'oc process' command!
	echo.
	GOTO :EOF
)

echo.
echo Setting up secrets link for kieserver user and password...
echo.
call oc create secret generic rhpam-credentials --from-literal=KIE_ADMIN_USER=%KIE_ADMIN_USER% --from-literal=KIE_ADMIN_PWD=%KIE_ADMIN_PWD%

if not "%ERRORLEVEL%" == "0" (
  echo.
  echo Error occurred during 'oc secrets' creating kieserver user and password!
  echo.
  GOTO :EOF
)


echo.
echo Creating a new application using CRC catalog image...
echo.
call oc new-app --template=rhdm%VERSION%-authoring -p APPLICATION_NAME="%OCP_APP%" -p CREDENTIALS_SECRET="rhpam-credentials" -p DECISION_CENTRAL_HTTPS_SECRET="decisioncentral-app-secret" -p KIE_SERVER_HTTPS_SECRET="kieserver-app-secret" -p MAVEN_REPO_USERNAME="%KIE_ADMIN_USER%" -p MAVEN_REPO_PASSWORD="%KIE_ADMIN_PWD%" -p DECISION_CENTRAL_VOLUME_CAPACITY="%PV_CAPACITY%"

if not "%ERRORLEVEL%" == "0" (
  echo.
	echo Error occurred during 'oc new-app' command!
	echo.
	GOTO :EOF
)

echo.
echo =================================================================================
echo =                                                                               =
echo =  Login to Red Hat decision Manager to start developing rules projects at:     =
echo =                                                                               =
echo =   https://%OCP_APP%-rhdmcentr-%OCP_PRJ%.%HOST_APPS%     =
echo =                                                                               =
echo =    Log in: [ u:erics / p:redhatdm1! ]                                         =
echo =                                                                               =
echo =    Others:                                                                    =
echo =            [ u:kieserver / p:redhatdm1! ]                                     =
echo =                                                                               =
echo =  Note: it takes a few minutes to expose the service...                        =
echo =                                                                               =
echo =================================================================================
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

 echo The default option is to run this using Code Ready Containers, an OpenShift Container
  echo Platform for your local machine. This host has been set by default in the variables at
	echo the top of this script. You can modify if needed for your own host and ports by mofifying
	echo these variables:
	echo.
	echo     HOST_IP=api.crc.testing
  echo     HOST_PORT=6443
	echo.
	echo It's also possible to install this project on a personal Code Ready Containers installation, just point
  echo this installer at your installation by passing an IP address of the hosting cluster:
	echo.
	echo    $ init.bat IP
	echo.
	echo IP could look like: 192.168.99.100
	echo.
	echo Both methodes are validated by the install scripts.
	echo.

