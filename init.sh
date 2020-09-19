#!/bin/sh 
DEMO="CRC Quick Loan Bank Demo"
AUTHORS="Andrew Block, Eric D. Schabell, Duncan Doyle"
PROJECT="git@gitlab.com:redhatdemocentral/crc-quick-loan-bank-demo.git"
SRC_DIR=./installs
PRJ_DIR=./projects
SUP_DIR=./support
OC_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/"

# Adjust these variables to point to an OCP instance.
OPENSHIFT_USER=developer
OPENSHIFT_PWD=developer
HOST_IP=api.crc.testing    # set with CRC instance hostname or IP.
HOST_APPS=apps-crc.testing
HOST_PORT=6443
OCP_APP=quick-loan-bank
OCP_PRJ=appdev-in-cloud

KIE_ADMIN_USER=erics
KIE_ADMIN_PWD=redhatdm1!
PV_CAPACITY=1Gi
VERSION=77

# qlb project details.
PRJ_ID=loan-application
PRJ_REPO="https://github.com/jbossdemocentral/rhdm7-qlb-loan-demo-repo.git"
DELAY=300   # waiting max 5 min various container functions to startup.

# import container functions.
source support/container-functions.sh

# prints the documentation for this script.
function print_docs() 
{
  echo "The default option is to run this using Code Ready Containers, an OpenShift Container"
	echo "Platform for your local machine. This host has been set by default in the variables at"
	echo "the top of this script. You can modify if needed for your own host and ports by mofifying"
	echo "these variables:"
	echo
	echo "    HOST_IP=api.crc.testing"
  echo "    HOST_PORT=6443"
	echo
	echo "It's also possible to install this project on a personal Code Ready Container installation, just point"
  echo "this installer at your installation by passing an IP address of the hosting cluster:"
	echo
	echo "   $ ./init.sh IP"
	echo
	echo "IP could look like: 192.168.99.100"
	echo
	echo "Both methodes are validated by the install scripts."
	echo
}

# check for a valid passed IP address.
function valid_ip()
{
	local  ip=$1
	local  stat=1

	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		OIFS=$IFS
		IFS='.'
		ip=($ip)
		IFS=$OIFS
		[[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
		stat=$?
	fi

	return $stat
}

# wipe screen.
clear 

echo
echo "#####################################################################"
echo "##                                                                 ##"   
echo "##  Setting up the ${DEMO}                        ##"
echo "##                                                                 ##"   
echo "##                                                                 ##"   
echo "##  ####  #   # ####  #   #        #### #      ###  #   # ####     ##"
echo "##  #   # #   # #   # ## ##   #   #     #     #   # #   # #   #    ##"
echo "##  ####  ##### #   # # # #  ###  #     #     #   # #   # #   #    ##"
echo "##  # #   #   # #   # #   #   #   #     #     #   # #   # #   #    ##"
echo "##  #  #  #   # ####  #   #        #### #####  ###   ###  ####     ##"
echo "##                                                                 ##"   
echo "##  brought to you by,                                             ##"   
echo "##             ${AUTHORS}        ##"
echo "##                                                                 ##"   
echo "##  ${PROJECT}  ##"
echo "##                                                                 ##"   
echo "#####################################################################"
echo

# check for passed target IP.
if [ $# -eq 1 ]; then
	echo "Checking for host ip passed as command line variable."
	echo
	if valid_ip "$1" || [ "$1" == "$HOST_IP" ]; then
		echo "OpenShift host given is a valid IP..."
		HOST_IP=$1
		echo
		echo "Proceeding with OpenShift host: $HOST_IP..."
		echo
	else
		# bad argument passed.
		echo "Please provide a valid IP that points to an OpenShift installation..."
		echo
		print_docs
		echo
		exit
	fi
elif [ $# -gt 1 ]; then
	print_docs
	echo
	exit
elif [ $# -eq 0 ]; then
	# validate HOST_IP.
  if [ -z ${HOST_IP} ]; then
	  # no host name set yet.
	  echo "No host name set in HOST_IP..."
	  echo
		print_docs
		echo
		exit
	else
		# host ip set, echo and proceed with hostname.
		echo "You've manually set HOST to '${HOST_IP}' so we'll use that for your OpenShift Container Platform target."
		echo
	fi
fi

# make some checks first before proceeding.	
command -v oc version --client >/dev/null 2>&1 || { echo >&2 "OpenShift CLI tooling is required but not installed yet... download here (unzip and put on your path): ${OC_URL}"; exit 1; }
echo "OpenShift command line tools installed... checking for valid version..."
echo

echo "OpenShift commandline tooling is installed..."
echo 
echo "Logging in to OpenShift as $OPENSHIFT_USER..."
echo
oc login ${HOST_IP}:${HOST_PORT} --password=$OPENSHIFT_PWD --username=$OPENSHIFT_USER

if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc login' command!"
	exit
fi

echo
echo "Check for availability of correct version of Red Hat Decision Manager Authoring template..."
echo
oc get templates -n openshift rhdm${VERSION}-authoring >/dev/null 2>&1

if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc get template rhdm-authoring' command!"
	echo
	echo "Your container platform is mising this tempalte versoin in your catalog: rhdm${VERSION}-authoring"
	echo "Make sure you are using the correct version of Code Ready Containers as listed in project Readme file."
	echo
	exit
fi

echo
echo "Creating a new project..."
echo
oc new-project "$OCP_PRJ"

echo
echo "Setting up a secrets and service accounts..."
echo
oc process -f ${SUP_DIR}/app-secret-template.yaml -p SECRET_NAME=decisioncentral-app-secret | oc create -f -
oc process -f ${SUP_DIR}/app-secret-template.yaml -p SECRET_NAME=kieserver-app-secret | oc create -f -

if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc process' app-secrets command!"
	echo
	exit
fi

echo
echo "Setting up secrets link for kieserver user and password..."
echo
oc create secret generic rhpam-credentials --from-literal=KIE_ADMIN_USER=${KIE_ADMIN_USER} --from-literal=KIE_ADMIN_PWD=${KIE_ADMIN_PWD}

if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc secrets' creating kieserver user and password!"
	echo
	exit
fi

echo
echo "Processing to setup KIE-Server with CORS support..."
echo
oc process -f ${SUP_DIR}/rhdm${VERSION}-kieserver-cors.yaml \
	-p DOCKERFILE_REPOSITORY="http://www.github.com/redhatdemocentral/crc-quick-loan-bank-demo" \
	-p DOCKERFILE_REF="master" \
	-p DOCKERFILE_CONTEXT=${SUP_DIR}/rhdm${VERSION}-kieserver-cors 
 
if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc process' cors kie-server command!"
	exit
fi

echo
echo "Creating a new application using CRC RHDM catalog image..."
echo
oc new-app --template=rhdm$VERSION-authoring \
	-p APPLICATION_NAME="$OCP_APP" \
  -p DECISION_CENTRAL_HTTPS_SECRET="decisioncentral-app-secret" \
  -p KIE_SERVER_HTTPS_SECRET="kieserver-app-secret" \
	-p CREDENTIALS_SECRET="rhpam-credentials" \
	-p MAVEN_REPO_USERNAME="$KIE_ADMIN_USER" \
	-p MAVEN_REPO_PASSWORD="$KIE_ADMIN_PWD" \
  -p DECISION_CENTRAL_VOLUME_CAPACITY="$PV_CAPACITY"

if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc new-app' rhdm command!"
	exit
fi

echo
echo "Patch the KIE-Server to use CORS support..."
echo
oc patch dc/${OCP_APP}-kieserver --type='json' -p="[{'op': 'replace', 'path': '/spec/triggers/0/imageChangeParams/from/name', 'value': 'rhdm${VERSION}-kieserver-cors:latest'}]" >/dev/null 2>&1

if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc patch' kie-server cors support command!"
	exit
fi

if container_ready; then
	echo
	echo "The container has started..."
	echo
else
	echo "Exiting now with CodeReady Container started, but not sure if "
	echo "authoring environment is ready and did not install the demo project."
	echo
	exit
fi

echo "Creating a space for the project import..."
echo

if create_project_space; then
  echo "Creation of new space for project import started..."
  echo
else
  echo "Exiting now with CodeReady Container started, but not sure if "
  echo "authoring environment is ready and did not install the demo project."
	echo 
	exit
fi

echo "Validating new project space creation..."
echo

if validate_project_space; then
	echo "Creation of space successfully validated..."
	echo
else
	echo "Exiting now with CodeReady Container started, autorhing environment"
	echo "is ready, but unable to import the demo project."
	echo
	exit
fi

echo "Checking if project already exists, otherwise add it..."
echo

if project_exists; then
	echo "Demo project already exists..."
	echo 
else
	echo "Project does not exist, importing in to container..."
	echo
	
	if project_imported; then
		echo "Imported project successfully..."
		echo
	else
	  echo "Exiting now with Code ReadyContainer started, authoring environment"
	  echo "is ready, but unable to import the demo project."
	  echo
		exit
	fi
fi

echo
echo "Creating a new application using CRC Node.js catalog image..."
echo
oc new-app nodejs:12~https://github.com/redhatdemocentral/${OCP_APP}#master \
	--name=qlb-client-application \
	--context-dir=${PRJ_DIR}/application-ui \
	-e NODE_ENV=development \
	--build-env NODE_ENV=development

if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc new-app' node.js command!"
	exit
fi

echo
echo "Retrieve KIE-Server route anbd put into conifg file..."
echo
KIESERVER_ROUTE=$(oc get route insecure-${OCP_APP}-kieserver | awk 'FNR > 1 {print $2}')
sed s/.*kieserver_host.*/\ \ \ \ \'kieserver_host\'\ :\ \'$KIESERVER_ROUTE\',/g ${PRJ_DIR}/application-ui/config/config.js.orig > ${PRJ_DIR}/application-ui/config/config.js.temp.1
sed s/.*kieserver_port.*/\ \ \ \ \'kieserver_port\'\ :\ \'80\'',/g ${PRJ_DIR}/application-ui/config/config.js.temp.1 > ${PRJ_DIR}/application-ui/config/config.js.temp.2
mv ${PRJ_DIR}/application-ui/config/config.js.temp.2 ${PRJ_DIR}/application-ui/config/config.js
rm ${PRJ_DIR}/application-ui/config/config.js.temp*

echo
echo "Creating config-map for client application..."
echo 
oc create configmap qlb-client-application-config-map --from-file=${PRJ_DIR}/application-ui/config/config.js

if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc create' config-map command!"
	exit
fi

echo
echo "Attaching config-map as volume to client application..."
echo
oc patch dc/qlb-client-application -p '{"spec":{"template":{"spec":{"volumes":[{"name": "volume-qlb-client-app-1", "configMap": {"name": "qlb-client-application-config-map", "defaultMode": 420}}]}}}}' >/dev/null 2>&1


if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc patch' client volumes command!"
	exit
fi

oc patch dc/qlb-client-application -p '{"spec":{"template":{"spec":{"containers":[{"name": "qlb-client-application", "volumeMounts":[{"name": "volume-qlb-cl    ient-app-1","mountPath":"/opt/app-root/src/config"}]}]}}}}' >/dev/null 2>&1

if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc patch' client containers command!"
	exit
fi

echo
echo "Patch the service to set targetPort to 3000..."
echo
oc patch svc/qlb-client-application --type='json' -p="[{'op': 'replace', 'path': '/spec/ports/0/targetPort', 'value': 3000}]" >/dev/null 2>&1


if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc patch' client targetPort command!"
	exit
fi

echo
echo "Expose the client application service (route)..."
echo 
oc expose svc/qlb-client-application

if [ "$?" -ne "0" ]; then
	echo
	echo "Error occurred during 'oc expose' client route command!"
	exit
fi

echo
echo "========================================================================"
echo "=                                                                      ="
echo "=  Login to Red Hat Decision Manager to exploring process automation   ="
echo "=  development at:                                                     ="
echo "=                                                                      ="
echo "=   https://${OCP_APP}-rhdmcentr-${OCP_PRJ}.${HOST_APPS}     ="
echo "=                                                                      ="
echo "=    Log in: [ u:erics / p:redhatdm1! ]                                ="
echo "=                                                                      ="
echo "=    Others:                                                           ="
echo "=            [ u:kieserver / p:redhatdm1! ]                            ="
echo "=                                                                      ="
echo "=  See README.md for general details to run the various demo cases.    ="
echo "=                                                                      ="
echo "=  Note: it takes a few minutes to expose the service...               ="
echo "=                                                                      ="
echo "========================================================================"
echo


