#!/bin/sh

# Remove old config and rebuild.
rm -Rf /etc/tinc

# Incase we have no networks at all, at least make sure this exists.
mkdir -p /etc/tinc/
touch /etc/tinc/nets.boot

SHELL_API=`which cli-shell-api`

# Ensure we have a session.
MYSESSION="false"
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

  function atexit() {
    $SHELL_API teardownSession
  }
  trap atexit EXIT
fi;


net_list=$($SHELL_API listNodes protocols tinc)
eval "NETS=($net_list)"
for net in "${NETS[@]}"; do
  mkdir -p /etc/tinc/$net/hosts;

  config_list=$($SHELL_API listNodes protocols tinc $net)
  eval "CONFIG_LIST=($config_list)"
  for cfg in "${CONFIG_LIST[@]}"; do
    if [ "${cfg}" = "host" ]; then
      host_list=$($SHELL_API listNodes protocols tinc $net host)
      eval "HOST_LIST=($host_list)"

      for host in "${HOST_LIST[@]}"; do
        HOSTPUBKEY=""
        host_config_list=$($SHELL_API listNodes protocols tinc $net host $host)
        eval "HOST_CONFIG_LIST=($host_config_list)"
        for hcfg in "${HOST_CONFIG_LIST[@]}"; do
          if [ "${hcfg}" = "publickey" ]; then
            HOSTPUBKEY=$($SHELL_API returnValue protocols tinc $net host $host $hcfg)
          else
            FOUND=0
            values=$($SHELL_API returnValues protocols tinc $net host $host $hcfg)
            eval "VALUES=($values)";
            for val in "${VALUES[@]}"; do
              if [ "${val}" != "" ]; then
                echo "${hcfg} ${val}" >> /etc/tinc/$net/hosts/$host
              fi;
              FOUND=1
            done;

            if [ "${FOUND}" = "0" ]; then
              val=$($SHELL_API returnValue protocols tinc $net host $host $hcfg)
              if [ "${val}" != "" ]; then
                echo "${hcfg} ${val}" >> /etc/tinc/$net/hosts/$host
              fi;
            fi;
          fi;
        done;
        if [ "${HOSTPUBKEY}" != "" ]; then
          echo '' >> /etc/tinc/$net/hosts/$host
          echo '-----BEGIN RSA PUBLIC KEY-----' >> /etc/tinc/$net/hosts/$host
          echo "${HOSTPUBKEY}" | sed -r 's/(.{65})/\1\n/g' >> /etc/tinc/$net/hosts/$host
          echo '-----END RSA PUBLIC KEY-----' >> /etc/tinc/$net/hosts/$host
        fi;
      done;
    elif [ "${cfg}" = "proxy" ]; then
      # TODO: Proxy stuff.
      echo -n ""
    elif [ "${cfg}" = "tinc-up" -o "${cfg}" = "tinc-down" ]; then
      val=$($SHELL_API returnValue protocols tinc $net $cfg)
      if [ -e "${val}" ]; then
        ln -s ${val} /etc/tinc/$net/$cfg
      fi;
    elif [ "${cfg}" = "myip" -o "${cfg}" = "enabled" ]; then
      # Do nothing. This is a vyatta-tinc config setting, not a tinc config setting.
      echo -n ""
    elif [ "${cfg}" = "privatekey" ]; then
      PRIVATEKEY=$($SHELL_API returnValue protocols tinc $net privatekey)
      if [ "${PRIVATEKEY}" != "" ]; then
        echo '-----BEGIN RSA PRIVATE KEY-----' >> /etc/tinc/$net/rsa_key.priv
        echo "${PRIVATEKEY}" | sed -r 's/(.{65})/\1\n/g' >> /etc/tinc/$net/rsa_key.priv
        echo '-----END RSA PRIVATE KEY-----' >> /etc/tinc/$net/rsa_key.priv
        chmod 600 /etc/tinc/$net/rsa_key.priv
      fi;
    elif [ "${cfg}" = "generatekeys" ]; then
      GENERATE=$($SHELL_API returnValue protocols tinc $net generatekeys)
      PRIVATEKEY=$($SHELL_API returnValue protocols tinc $net privatekey)
      if [ "${GENERATE}" = "true" -a "${PRIVATEKEY}" = "" -a -e "/usr/sbin/tincd" ]; then
        MYNAME=$($SHELL_API returnValue protocols tinc $net name)
        if [ "${MYNAME}" != "" ]; then
          TEMPDIR=`mktemp -d`
          echo "" | /usr/sbin/tincd -K -c "${TEMPDIR}" 2>/dev/null
          MYPUBLICKEY=$(cat "${TEMPDIR}/rsa_key.pub" | egrep -v "^(.*(BEGIN|END) RSA.*|)$" | tr -d '\n')
          MYPRIVATEKEY=$(cat "${TEMPDIR}/rsa_key.priv" | egrep -v "^(.*(BEGIN|END) RSA.*|)$" | tr -d '\n')
          /opt/vyatta/sbin/my_set protocols tinc $net privatekey "${MYPRIVATEKEY}"
          /opt/vyatta/sbin/my_set protocols tinc $net host ${MYNAME} publickey "${MYPUBLICKEY}"
          if [ "${MYSESSION}" = "true" ]; then
            /opt/vyatta/sbin/my_commit 2>&1
            exit $?
          fi;
          
          cp "${TEMPDIR}/rsa_key.priv" /etc/tinc/${net}/rsa_key.priv
          if [ -e "/etc/tinc/${net}/hosts/${MYNAME}" ]; then
            cat "${TEMPDIR}/rsa_key.pub" >> "/etc/tinc/${net}/hosts/${MYNAME}"
          fi;
          rm -Rf "${TEMPDIR}"
        fi;
      fi;
    else
      FOUND=0
      values=$($SHELL_API returnValues protocols tinc $net $cfg)
      eval "VALUES=($values)";
      for val in "${VALUES[@]}"; do
        if [ "${val}" != "" ]; then
          echo "${cfg} ${val}" >> /etc/tinc/$net/tinc.conf
        fi;
        FOUND=1
      done;

      if [ "${FOUND}" = "0" ]; then
        val=$($SHELL_API returnValue protocols tinc $net $cfg)
        if [ "${val}" != "" ]; then
          echo "${cfg} ${val}" >> /etc/tinc/$net/tinc.conf
        fi;
      fi;
    fi;
  done;

  if [ ! -e /etc/tinc/$net/tinc-up ]; then
    echo '#!/bin/sh' > /etc/tinc/$net/tinc-up
    echo 'ip link set $INTERFACE up' >> /etc/tinc/$net/tinc-up

    values=$($SHELL_API returnValues protocols tinc $net myip)
    eval "VALUES=($values)";
    for val in "${VALUES[@]}"; do
      if [ "${val}" != "" ]; then
        echo "ip addr add ${val} dev \$INTERFACE" >> /etc/tinc/$net/tinc-up
      fi;
    done;

    chmod a+x /etc/tinc/$net/tinc-up
  fi;
     
  NET_ENABLED=$($SHELL_API returnValue protocols tinc $net enabled)

  if [ "${NET_ENABLED}" = "true" ]; then
    echo $net >> /etc/tinc/nets.boot
  else
    rm -Rf /etc/tinc/$net/
  fi;
done;

# If tinc is installed, then poke it a bit.
if [ -e /etc/init.d/tinc ]; then
  # Make sure tinc is running for all networks
  /etc/init.d/tinc start >/dev/null 2>&1

  # Reload all networks.
  /etc/init.d/tinc reload >/dev/null 2>&1
fi;

# Kill networks that no longer exist.
for TINCPID in `ls /var/run/tinc.*.pid 2>/dev/null`; do
  TINCNET=`echo ${TINCPID} | sed -r 's/.*tinc\.(.*)\.pid/\1/'`
  
  if [ ! -e "/etc/tinc/${TINCNET}/" ]; then
    kill -TERM $(cat ${TINCPID}) >/dev/null 2>&1
    rm ${TINCPID};
  fi;
done;
