#!/bin/bash

########################################
# Allow specifying TINC_DIR environment variable.
########################################
if [ "${TINC_DIR}" = "" ]; then
	TINC_DIR="/etc/tinc"
fi;

########################################
# Remove old config and rebuild.
########################################
rm -Rf ${TINC_DIR}

# Incase we have no networks at all, at least make sure these exist so that the tinc startup script doesn't complain
mkdir -p ${TINC_DIR}
touch ${TINC_DIR}/nets.boot


########################################
# Make sure we have a config session.
########################################
SHELL_API=`which cli-shell-api`

# Did we set up the session, or was it already set up for us?
MYSESSION="false"
# Ensure we have a session.
$SHELL_API inSession
if [ $? -ne 0 ]; then
	# Obtain session environment
	session_env=$($SHELL_API getSessionEnv $PPID)

	# Evaluate environment string
	eval $session_env

	# Setup the session
	$SHELL_API setupSession
	$SHELL_API inSession
	if [ $? -ne 0 ]; then
		echo "Something went wrong setting up session."
		exit 1;
	fi
	MYSESSION="true"

	# Make sure we teardown the session when we exit if we created it.
	function atexit() {
		$SHELL_API teardownSession
	}
	trap atexit EXIT
fi;


########################################
# Wrapper function for listNodes, this will put the result into the global
# variable passed as the first param, all other params are passed to listNodes
########################################
getNodes() {
	RESULT=$1
	shift
	list=$($SHELL_API listNodes ${@})
	eval $RESULT="($list)"
}

########################################
# Wrapper function for returnValues, this will put the result into the global
# variable passed as the first param, all other params are passed to returnValues
########################################
getValues() {
	RESULT=$1
	shift
	list=$($SHELL_API returnValues ${@})
	eval $RESULT="($list)"
}

########################################
# Echo the value (or values if multi) of a given setting
# All params are passed to getValues as the second-onwards params.
########################################
echoKeyValue() {
	# The key is the last value in the parameters
	KEY="${@:$#}"

	# isMulti doesn't appear to work on EdgeOS, so we'll firstly try and get
	# multiple values,
	FOUND=0
	getValues VALUES ${@}
	for val in "${VALUES[@]}"; do
		if [ "${val}" != "" ]; then
			echo "${KEY} ${val}"
		fi;
		FOUND=1
	done;

	# We didn't get any values from getValues, so this might be a non-multi
	# setting
	if [ "${FOUND}" = "0" ]; then
		val=$($SHELL_API returnValue ${@})
		if [ "${val}" != "" ]; then
			echo "${KEY} ${val}"
		fi;
	fi;
}

########################################
# Format an RSA Key nicely.
# First param is the key type (PUBLIC/PRIVATE)
# Second param is the key
########################################
formatKey() {
	TYPE="${1}"
	KEY="${2}"

	echo ""
	echo "-----BEGIN RSA ${TYPE} KEY-----"
	echo "${KEY}" | sed -r 's/(.{65})/\1\n/g'
	echo "-----END RSA ${TYPE} KEY-----"
}


########################################
# Run through creating the config, this recursively reads the tinc config tree
########################################
getNodes NETS protocols tinc
for net in "${NETS[@]}"; do
	NET_DIR=${TINC_DIR}/${net};
	mkdir -p ${NET_DIR}/hosts;

	getNodes CONFIG_LIST protocols tinc $net
	for cfg in "${CONFIG_LIST[@]}"; do

		########################################
		# Host Related Settings
		########################################
		if [ "${cfg}" = "host" ]; then
			getNodes HOST_LIST protocols tinc $net host
			for host in "${HOST_LIST[@]}"; do
				HOST_FILE=${NET_DIR}/hosts/${host}
				HOSTPUBKEY=""

				# Get all settings for this host
				getNodes HOST_CONFIG_LIST protocols tinc $net host $host
				for hcfg in "${HOST_CONFIG_LIST[@]}"; do

					########################################
					# Host Public Key, store this for later.
					########################################
					if [ "${hcfg}" = "publickey" ]; then
						HOSTPUBKEY=$($SHELL_API returnValue protocols tinc $net host $host $hcfg)

					########################################
					# Host Scripts
					########################################
					elif [ "${gcfg}" = "up" -o "${cfg}" = "down" ]; then
						val=$($SHELL_API returnValue protocols tinc $net host $host $hcfg)
						if [ -e "${val}" ]; then
							ln -s ${val} ${NET_DIR}/hosts/${host}-${hcfg}
						fi;

					########################################
					# All other settings are just dropped straight into the config file.
					########################################
					else
						echoKeyValue protocols tinc $net host $host $hcfg >> ${HOST_FILE}
					fi;
				done;

				########################################
				# Actually add the Public Key to the config file.
				########################################
				if [ "${HOSTPUBKEY}" != "" ]; then
					formatKey "PUBLIC" "${HOSTPUBKEY}" >> ${HOST_FILE}
				fi;
			done;

		########################################
		# Proxy Related Settings
		########################################
		elif [ "${cfg}" = "proxy" ]; then
			# TODO: Proxy stuff.
			echo -n ""

		########################################
		# Custom Scripts
		########################################
		elif [ "${cfg}" = "tinc-up" -o "${cfg}" = "tinc-down" -o "${cfg}" = "host-up" -o "${cfg}" = "host-down" -o "${cfg}" = "subnet-up" -o "${cfg}" = "subnet-down" ]; then
			val=$($SHELL_API returnValue protocols tinc $net $cfg)
			if [ -e "${val}" ]; then
				ln -s ${val} ${NET_DIR}/${cfg}
			fi;

		########################################
		# My IP addresses (used when creating our own tinc-up script)
		########################################
		elif [ "${cfg}" = "myip" -o "${cfg}" = "enabled" ]; then
			# Do nothing. This is a vyatta-tinc config setting, not a tinc config setting.
			echo -n ""

		########################################
		# Private Key
		########################################
		elif [ "${cfg}" = "privatekey" ]; then
			PRIVATEKEY=$($SHELL_API returnValue protocols tinc $net privatekey)
			if [ "${PRIVATEKEY}" != "" ]; then
				formatKey "PRIVATE" "${HOSTPUBKEY}" >> ${NET_DIR}/rsa_key.priv
				chmod 600 ${NET_DIR}/rsa_key.priv
			fi;

		########################################
		# Generate Keys
		########################################
		elif [ "${cfg}" = "generatekeys" ]; then
			# Do we actually want to generate keys?
			# generatekeys must be "true", privatekey must be "" and tinc must be installed.
			GENERATE=$($SHELL_API returnValue protocols tinc $net generatekeys)
			PRIVATEKEY=$($SHELL_API returnValue protocols tinc $net privatekey)
			if [ "${GENERATE}" = "true" -a "${PRIVATEKEY}" = "" -a -e "/usr/sbin/tincd" ]; then
				# What is the name of this host, this is needed to put the public key in the right place
				MYNAME=$($SHELL_API returnValue protocols tinc $net name)
				if [ "${MYNAME}" != "" ]; then
					# Incase  we are half-way through dumping config, we will generate the
					# keys in a new directory so that they are in predictable places and
					# so that tincd doesn't write to any files we don't want it to.
					TEMPDIR=`mktemp -d`
					echo "" | /usr/sbin/tincd -K -c "${TEMPDIR}" 2>/dev/null

					# Extract the keys.
					MYPUBLICKEY=$(cat "${TEMPDIR}/rsa_key.pub" | egrep -v "^(.*(BEGIN|END) RSA.*|)$" | tr -d '\n')
					MYPRIVATEKEY=$(cat "${TEMPDIR}/rsa_key.priv" | egrep -v "^(.*(BEGIN|END) RSA.*|)$" | tr -d '\n')

					# Save the keys
					/opt/vyatta/sbin/my_set protocols tinc $net privatekey "${MYPRIVATEKEY}"
					/opt/vyatta/sbin/my_set protocols tinc $net host ${MYNAME} publickey "${MYPUBLICKEY}"

					# Put the keys where tinc will find them.
					cp "${TEMPDIR}/rsa_key.priv" ${NET_DIR}/rsa_key.priv
					if [ -e "${NET_DIR}/hosts/${MYNAME}" ]; then
						cat "${TEMPDIR}/rsa_key.pub" >> "${NET_DIR}/hosts/${MYNAME}"
					fi;

					# Remove the temporary directory.
					rm -Rf "${TEMPDIR}"

					# If we created the config session ourselves, then the script was run
					# outside of a config session, so we need to commit the config changes
					# we just made when generating the keys.
					if [ "${MYSESSION}" = "true" ]; then
						/opt/vyatta/sbin/my_commit 2>&1
						# Exit immediately, as my_commit will already cause this script to
						# re-run to finish off generating any config we don't get a chance
						# to finish!
						exit $?
					fi;
				fi;
			fi;

		########################################
		# Everything else just gets dumped into the config as-is
		########################################
		else
			echoKeyValue protocols tinc $net $cfg >> ${NET_DIR}/tinc.conf
		fi;
	done;


	########################################
	# Create our own tinc-up scripts if one has not already been specified.
	########################################
	if [ ! -e ${NET_DIR}/tinc-up ]; then
		echo '#!/bin/sh' > ${NET_DIR}/tinc-up
		echo 'ip link set $INTERFACE up' >> ${NET_DIR}/tinc-up

		getValues VALUES protocols tinc $net myip
		for val in "${VALUES[@]}"; do
			if [ "${val}" != "" ]; then
				echo "ip addr add ${val} dev \$INTERFACE" >> ${NET_DIR}/tinc-up
			fi;
		done;

		chmod a+x ${NET_DIR}/tinc-up
	fi;


	########################################
	# Check if this network is enabled, and add to nets.boot if it is, or remove the config if not.
	########################################
	NET_ENABLED=$($SHELL_API returnValue protocols tinc $net enabled)

	if [ "${NET_ENABLED}" = "true" ]; then
		echo $net >> ${TINC_DIR}/nets.boot
	else
		rm -Rf ${NET_DIR}/
	fi;
done;

########################################
# Post-Processing only if TINC_DIR is /etc/tinc
########################################
if [ "${TINC_DIR}" = "/etc/tinc" ]; then
	# If TINC is actually installed, then we need to poke it a bit.
	if [ -e /etc/init.d/tinc ]; then
		# Make sure tinc is running for all networks, this will start new ones and complain about existing ones.
		/etc/init.d/tinc start >/dev/null 2>&1

		# Reload all networks, this lets us pick up changes to existing networks.
		/etc/init.d/tinc reload >/dev/null 2>&1
	fi;

	# Kill daemon for networks that no longer exist.
	for TINCPID in `ls /var/run/tinc.*.pid 2>/dev/null`; do
		TINCNET=`echo ${TINCPID} | sed -r 's/.*tinc\.(.*)\.pid/\1/'`

		if [ ! -e "${TINC_DIR}/${TINCNET}/" ]; then
			kill -TERM $(cat ${TINCPID}) >/dev/null 2>&1
			rm ${TINCPID};
		fi;
	done;
fi;
