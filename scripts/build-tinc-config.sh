#!/bin/sh

rm -Rf /etc/tinc

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


net_list=$($SHELL_API listActiveNodes protocols tinc)
eval "NETS=($net_list)"
for net in "${NETS[@]}"; do
        mkdir -p /etc/tinc/$net/hosts;

        config_list=$($SHELL_API listActiveNodes protocols tinc $net)
        eval "CONFIG_LIST=($config_list)"
        for cfg in "${CONFIG_LIST[@]}"; do
                if [ "${cfg}" = "host" ]; then
                        host_list=$($SHELL_API listActiveNodes protocols tinc $net host)
                        eval "HOST_LIST=($host_list)"

                        for host in "${HOST_LIST[@]}"; do
                                host_config_list=$($SHELL_API listActiveNodes protocols tinc $net host $host)
                                eval "HOST_CONFIG_LIST=($host_config_list)"
                                for hcfg in "${HOST_CONFIG_LIST[@]}"; do
                                        FOUND=0
                                        values=$($SHELL_API returnActiveValues protocols tinc $net host $host $hcfg)
                                        eval "VALUES=($values)";
                                        for val in "${VALUES[@]}"; do
                                                if [ "${val}" != "" ]; then
                                                        echo "${hcfg} ${val}" >> /etc/tinc/$net/hosts/$host
                                                fi;
                                                FOUND=1
                                        done;

                                        if [ "${FOUND}" = "0" ]; then
                                                val=$($SHELL_API returnActiveValue protocols tinc $net host $host $hcfg)
                                                if [ "${val}" != "" ]; then
                                                        echo "${hcfg} ${val}" >> /etc/tinc/$net/hosts/$host
                                                fi;
                                        fi;

                                done;
                        done;
                elif [ "${cfg}" = "proxy" ]; then
                        # TODO: Proxy stuff.
                        echo -n ""
                elif [ "${cfg}" = "tinc-up" -o "${cfg}" = "tinc-down" ]; then
                        val=$($SHELL_API returnActiveValue protocols tinc $net $cfg)
                        if [ -e "${val}" ]; then
                                ln -s ${val} /etc/tinc/$net/$cfg
                        fi;
                elif [ "${cfg}" = "myip"  ]; then
                        # Do nothing, we use this later.
                        echo -n ""
                else
                        FOUND=0
                        values=$($SHELL_API returnActiveValues protocols tinc $net $cfg)
                        eval "VALUES=($values)";
                        for val in "${VALUES[@]}"; do
                                if [ "${val}" != "" ]; then
                                        echo "${cfg} ${val}" >> /etc/tinc/$net/tinc.conf
                                fi;
                                FOUND=1
                        done;

                        if [ "${FOUND}" = "0" ]; then
                                val=$($SHELL_API returnActiveValue protocols tinc $net $cfg)
                                if [ "${val}" != "" ]; then
                                        echo "${cfg} ${val}" >> /etc/tinc/$net/tinc.conf
                                fi;
                        fi;
                fi;
        done;

        if [ ! -e /etc/tinc/$net/tinc-up ]; then
                echo '#!/bin/sh' > /etc/tinc/$net/tinc-up
                echo 'ip link set $INTERFACE up' >> /etc/tinc/$net/tinc-up

                values=$($SHELL_API returnActiveValues protocols tinc $net myip)
                eval "VALUES=($values)";
                for val in "${VALUES[@]}"; do
                        if [ "${val}" != "" ]; then
                                echo "ip addr add ${val} dev \$INTERFACE" >> /etc/tinc/$net/tinc-up
                        fi;
                done;

                chmod a+x /etc/tinc/$net/tinc-up
        fi;

done;
