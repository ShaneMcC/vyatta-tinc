#!/bin/sh

SHELL_API=`which cli-shell-api`

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

  function atexit() {
    $SHELL_API teardownSession
  }
  trap atexit EXIT
fi;

if [ "${1}" = "networklist" ]; then
  net_list=$($SHELL_API listNodes protocols tinc)
  eval "NETS=($net_list)"
  for net in "${NETS[@]}"; do  
    echo $net
  done;
elif [ "${1}" = "status" ]; then
  if [ ! -e "/etc/init.d/tinc" ]; then
    echo "WARNING: tinc is not installed."
  fi;

  net_list=$($SHELL_API listNodes protocols tinc)
  eval "NETS=($net_list)"
  for net in "${NETS[@]}"; do  
    NET_ENABLED=$($SHELL_API returnValue protocols tinc $net enabled)

    if [ "${NET_ENABLED}" = "true" ]; then
      echo -n "$net: "
      if [ -e "/var/run/tinc.${net}.pid" ]; then
        echo "Running ($(cat "/var/run/tinc.${net}.pid"))";
      else
        echo "Not running";
      fi;
    else
      echo "$net: Disabled"
    fi;
  done;
elif [ "${1}" = "connections" -o "${1}" = "statistics" ]; then
  net="${2}"
  if [ "${1}" = "connections" ]; then
    SIGNAL="USR1"
  elif [ "${1}" = "statistics" ]; then
    SIGNAL="USR2"
  fi;

  # Make sure syslog will log what we need for the show commands.
  if [ ! -e "/etc/rsyslog.d/vyatta-tinc.conf" -a -e "/etc/rsyslog.d/" ]; then
    echo ':syslogtag, startswith, "tinc."   -/var/log/messages' > /etc/rsyslog.d/vyatta-tinc.conf
    /etc/init.d/rsyslog restart >/dev/null 2>&1
  fi;

  if [ "${net}" != "" ]; then
    if [ -e "/var/run/tinc.${net}.pid" ]; then
      echo "Attempting to get ${1} information from tinc: "
      kill -${SIGNAL} $(cat "/var/run/tinc.${net}.pid") 2>&1

      cat /var/log/messages | grep "tinc.${net}\[$(cat "/var/run/tinc.${net}.pid")\]" | grep `date +%H:%M:%S` | cut -f 4- -d:
    else
      echo "Unknown tinc instance, or tinc instance not currently running: ${net}"
    fi;
  else
    echo "No tinc instance specified."
  fi;
elif [ "${1}" = "logging" ]; then
  net="${2}"
  if [ "${net}" != "" ]; then
    if [ "${3}" = "all" ]; then
      echo "All log entries:"
      cat /var/log/messages | grep "tinc.${net}" | tail -n 50
    else
      if [ -e "/var/run/tinc.${net}.pid" ]; then
        echo "Recent log entries:"
        cat /var/log/messages | grep "tinc.${net}\[$(cat "/var/run/tinc.${net}.pid")\]" | tail -n 50
      else
        echo "Unknown tinc instance, or tinc instance not currently running: ${net}"
      fi;
    fi;
  else
    echo "No tinc instance specified."
  fi;
else
  echo "Unknown command."
fi;
