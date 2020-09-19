@ECHO OFF

REM Collection of container functions used in demos.
REM

REM prints the documentation for this script.
REM
:printDocs

	echo The default option is to run this using Code Ready Containers, an OpenShift Container
	echo Platform for your local machine. This host has been set by default in the variables at
	echo the top of this script. You can modify if needed for your own host and ports by mofifying
	echo these variables:
	echo.
	echo     HOST_IP=api.crc.testing
	echo     HOST_PORT=6443
	echo.
	echo It's also possible to install this project on any available OpenShift installation, just point
	echo this installer at your installation by passing an IP address of the hosting cluster:
	echo.
	echo    $ init.bat IP
	echo.
	echo IP could look like: 192.168.99.100
	echo.
	echo Both methodes are validated by the install scripts.
	echo.

:endPrintDocs


REM check for a valid passed IP address.
REM
:validateIP ipAddress [returnVariable]

	setlocal

	set "_return=1"

	echo %~1^| findstr /b /e /r "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*" >nul

	if not errorlevel 1 for /f "tokens=1-4 delims=." %%a in ("%~1") do (
		if %%a gtr 0 if %%a lss 255 if %%b leq 255 if %%c leq 255 if %%d gtr 0 if %%d leq 254 set "_return=0"
	)

	endlocal & ( if not "%~2"=="" set "%~2=%_return%" ) & exit /b %_return%

:endValidateIP

REM check if container is ready.
REM
:containerReady [returnVariable]

  setlocal

	set "_return=0"
	set count=0
	set created=false

	:loop
  set status=call curl -u %KIE_ADMIN_USER%:%KIE_ADMIN_PWD% --output NUL --write-out "%{http_code}" --silent --head --fail "http://insecure-%OCP_APP%-rhdmcentr-%OCP_PRJ%.%HOST_APPS%/rest/spaces"

	if %status% EQU 200 {
		set created=true
		GOTO :endLoop
	} 

	echo Container has not started yet.. waiting on container [ %count%s ]
	timeout /t 5 /nobreak > NUL
	set /A count=count+5

	if %count% GTR %DELAY% goto loop

	:endLoop

	if %created% EQU "false" {
	  set "_return=1"
	  echo.
		echo The business central container failed to start inside %DELAY% sec,
		echo maybe try to increase the wait time by increasing  the value of variable
		echo 'DELAY' located at top of this script?
		echo.
		exit /b %_return% 
	}

	REM returning true.
	exit /b %_return%

	endlocal

:endContainerReady


REM Checking if project already exists.
REM
:projectExists [returnVariable]

  setlocal

	set "_return=0"

	set status=call curl -u %KIE_ADMIN_USER%:%KIE_ADMIN_PWD% --output NUL --write-out "%{http_code}" --silent --head --fail "http://insecure-%OCP_APP%-rhdmcentr-%OCP_PRJ%.%HOST_APPS%/rest/spaces/MySpace/projects/%PRJ_ID%"

	if %status% EQU 200 {
    echo Demo project already exists...
		echo
	} else {
    REM Importing project.
		set "_return=1"
		exit /b %_return%
	}

	exit /b %_return%

	endlocal

:endProjectExists


REM Importing project.
REM
:projectImported [returnVariable]

  setlocal

	set "_return=0"
	set count=0
	set created=false

	:loop
	set  status=call curl -H "Accept: application/json" -H "Content-Type: application/json" -f -X POST -d "{\"name\":\"%PRJ_ID%\", \"gitURL\":\"%PRJ_REPO%\"}" -u %KIE_ADMIN_USER%:%KIE_ADMIN_PWD% --silent --output NUL --write-out "%{http_code}" "http://insecure-%OCP_APP%-rhdmcentr-${OCP_PRJ}.${HOST_APPS}/rest/spaces/MySpace/git/clone"

  if %status% EQU 202 {
    set created=true
    GOTO :endLoop
  }
 	 
	echo Importing demo repository and restAPI not ready... waiting on async API  [ %count%s ]
  timeout /t 5 /nobreak > NUL
  set /A count=count+5
 
  if %count% GTR %DELAY% goto loop
 
  :endLoop
 
	if %created% EQU "false" {
    set "_return=1"
    echo.
	  echo The demo project failed to import inside %DELAY% sec, it's most likely an issue with
    echo the async nature of business central restAPI. After this installation script
	  echo completes, try running the install-demo.sh script in the 'support' directory.
    echo.
    exit /b %_return%
  }
 
	REM returning true.
	exit /b %_return%
 
  endlocal

:endProjectImported


:createProjectSpace [returnVariable]

  setlocal

	set "_return=0"

	set status=call curl -H "Accept: application/json" -H "Content-Type: application/json" -f -X POST -d "{ \"name\":\"MySpace\", \"description\":null, \"projects\":[], \"owner\":\"%KIE_ADMIN_USER%\", \"defaultGroupId\":\"com.myspace\"}" -u "%KIE_ADMIN_USER%:%KIE_ADMIN_PWD%" --silent --output NUL --write-out "%{http_code}" "http://insecure-%OCP_APP%-rhdmcentr-%OCP_PRJ%.%HOST_APPS%/rest/spaces"

	if %status% NEQ 202 {
	  set "_return=1"
	  echo Problem creating the space to import project to...
	  echo.
		exit /b %_return%
  }

	REM Creation of new space for project started.
	exit /b %_return%

	endlocal

:endCreateProjectSpace


:validateProjectSpace

  setlocal

	set "_return=0"

	set count=0
	set created=false

	:loop

	set status=call curl -u %KIE_ADMIN_USER%:%KIE_ADMIN_PWD% --output NUL --silent --head --fail --write-out "%{http_code}" "http://insecure-%OCP_APP%-rhdmcentr-%OCP_PRJ%.%HOST_APPS%/rest/spaces/MySpace"

	if %status% EQU 200 {
    set created=true
    GOTO :endLoop
  }
   
  echo Validating creation of new space... waiting on async API  [ %count%s ]
  timeout /t 5 /nobreak > NUL
  set /A count=count+5
   
  if %count% GTR %DELAY% goto loop
 
  :endLoop
    
  if %created% EQU "false" {
    set "_return=1"
    echo.
		echo The creation of a new space failed inside %DELAY% sec.
    echo.
    exit /b %_return%
  }
    
  REM returning true.
  exit /b %_return%

	endlocal

:endValidateProjectSpace
		
