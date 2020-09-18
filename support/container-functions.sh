#!/bin/sh 

# Collection of container functions used in demos.
#

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
	echo "It's also possible to install this project on personal Code Ready Containers installation, just point"
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

function container_ready()
{
	# check if container is ready.
	local count=0
	local created=false
	echo
	echo "DEBUG: waiting on http://insecure-${OCP_APP}-rhpamcentr-${OCP_PRJ}.${HOST_APPS}/rest/spaces"
	echo

	until [ $count -gt $DELAY ]
	do
		status=$(curl -u $KIE_ADMIN_USER:$KIE_ADMIN_PWD --output /dev/null --write-out "%{http_code}" \
		--silent --head --fail "http://insecure-${OCP_APP}-rhpamcentr-${OCP_PRJ}.${HOST_APPS}/rest/spaces")

		if [ ${status} -eq "200" ]; then
			created=true
			break
		fi
		
		echo "Container has not started yet... waiting on container  [ ${count}s ]"
		sleep 5
		let count=$count+5;
	done
	
	if [ $created == "false" ]; then
		echo
		echo "The container failed to start inside ${DELAY} sec, "
		echo "maybe try to increase the wait time by increasing  the value of variable"
		echo "'DELAY' located at top of this script?"
		echo
		return 1   # false
	fi
	
	return 0   # true
}

function project_exists()
{
	# checking if project already exists.
	status=$(curl -u $KIE_ADMIN_USER:$KIE_ADMIN_PWD --output /dev/null \
  --write-out "%{http_code}" --silent --head --fail                \
	"http://insecure-${OCP_APP}-rhpamcentr-${OCP_PRJ}.${HOST_APPS}/rest/spaces/MySpace/projects/${PRJ_ID}")

  if [ ${status} -eq "200" ]; then
		echo "Demo project already exists..."
		echo 
	else
		# importing project.
		return 1  # false
	fi

	return 0   # true
}

function project_imported()
{
	local count=0
	local created=false
	until [ $count -gt $DELAY ]
  do
	  status=$(curl -H "Accept: application/json" -H "Content-Type: application/json" -f -X POST \
		  -d "{\"name\":\"$PRJ_ID\", \"gitURL\":\"$PRJ_REPO\"}" \
		  -u $KIE_ADMIN_USER:$KIE_ADMIN_PWD --silent --output /dev/null --write-out "%{http_code}" \
		  "http://insecure-${OCP_APP}-rhpamcentr-${OCP_PRJ}.${HOST_APPS}/rest/spaces/MySpace/git/clone")
    if [ ${status} -eq "202" ]; then
      created=true
      break
    fi

	  echo "Importing demo repository and restAPI not ready... waiting on async API  [ ${count}s ]"
    sleep 5
    let count=$count+5;
  done

  if [ $created == "false" ]; then
	  echo
	  echo "The demo project failed to import inside ${DELAY} sec, it's most likely an issue with"
	  echo "the async nature of business central restAPI. After this installation script"
	  echo "completes, try running the install-demo.sh script in the 'support' directory."
	  echo
		return 1  # false
  fi

	return 0  # true
}

function create_project_space()
{
	status=$(curl -H "Accept: application/json" -H "Content-Type: application/json" -f -X POST \
		-d "{ \"name\":\"MySpace\", \"description\":null, \"projects\":[], \"owner\":\"$KIE_ADMIN_USER\", \"defaultGroupId\":\"com.myspace\"}" \
		-u "$KIE_ADMIN_USER:$KIE_ADMIN_PWD" --silent --output /dev/null --write-out "%{http_code}" \
		"http://insecure-${OCP_APP}-rhpamcentr-${OCP_PRJ}.${HOST_APPS}/rest/spaces")

	if [ ${status} -ne "202" ] ; then
		echo "Problem creating the space to import project to..."
		echo
		return 1  # false
	fi

	# create of new space for project started.
	return 0  # true
}

function validate_project_space()
{
	local count=0
	local created=false
	until [ $count -gt $DELAY ]
	do
		status=$(curl -u $KIE_ADMIN_USER:$KIE_ADMIN_PWD --output /dev/null \
			--silent --head --fail --write-out "%{http_code}" \
			"http://insecure-${OCP_APP}-rhpamcentr-${OCP_PRJ}.${HOST_APPS}/rest/spaces/MySpace")

		if [ ${status} -eq "200" ] ; then
			created=true
			break
		fi
	  
		echo "Validating creation of new space... waiting [ ${count}s ]"
		sleep 5
		let count=$count+5;
	done
	
	if [ $created == "false" ]; then
		echo
		echo "The creation of a new space failed inside ${DELAY} sec."
		echo
		return 1  # false
	fi

	# project space creation validated.
	return 0   # true
}

