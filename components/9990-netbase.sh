#!/bin/sh

#set -e

Netbase ()
{
	if [ -n "${NONETWORKING}" ]
	then
		return
	fi

	# FIXME: stop hardcoding overloading of initramfs-tools functions
	. /scripts/functions
	. /lib/live/boot/9990-initramfs-tools.sh

	log_begin_msg "Preconfiguring networking"

	IFFILE="/root/etc/network/interfaces"
	DNSFILE="/root/etc/resolv.conf"

	if [ "${STATICIP}" = "frommedia" ] && [ -e "${IFFILE}" ]
	then
		# will use existent /etc/network/interfaces
		log_end_msg
		return
	fi

cat > "${IFFILE}" << EOF
auto lo
iface lo inet loopback

EOF

	udevadm trigger
	udevadm settle

	if [ -z "${NETBOOT}" ] && [ -n "${STATICIP}" ] && [ "${STATICIP}" != "frommedia" ]
	then
		parsed=$(echo "${STATICIP}" | sed -e 's|,| |g')

		for ifline in ${parsed}
		do
			ifname="$(echo ${ifline} | cut -f1 -d ':')"
			ifaddress="$(echo ${ifline} | cut -f2 -d ':')"
			ifnetmask="$(echo ${ifline} | cut -f3 -d ':')"
			ifgateway="$(echo ${ifline} | cut -f4 -d ':')"
			nameserver="$(echo ${ifline} | cut -f5 -d ':')"

cat >> "${IFFILE}" << EOF
allow-hotplug ${ifname}
iface ${ifname} inet static
    address ${ifaddress}
    netmask ${ifnetmask}
EOF

			if [ -n "${ifgateway}" ]
			then

cat >> "${IFFILE}" << EOF
    gateway ${ifgateway}

EOF

			fi

			if [ -n "${nameserver}" ]
			then
				if [ -e "${DNSFILE}" ]
				then
					grep -v ^nameserver "${DNSFILE}" > "${DNSFILE}.tmp"
					mv "${DNSFILE}.tmp" "${DNSFILE}"
				fi

				echo "nameserver ${nameserver}" >> "${DNSFILE}"
			fi
		done
	else
		if [ -z "${NETBOOT}" ] || [ -n "${DHCP}" ]
		then
			# default, dhcp assigned
			method="dhcp"
		else
			# make sure that the preconfigured interface would not get reassigned by dhcp
			# on startup by ifup script - otherwise our root fs might be disconnected!
			method="manual"
		fi

		# iterate the physical interfaces and add them to the interfaces list and also add when ethdevice= called on cmdline
		if [ "${method}" != dhcp ] || ([ ! -x /root/usr/sbin/NetworkManager ] && [ ! -x /root/usr/sbin/wicd ]) || [ ! -z "${ETHDEVICE}" ]
		then
			for interface in /sys/class/net/eth* /sys/class/net/ath* /sys/class/net/wlan*
			do
				[ -e ${interface} ] || continue
				i="$(basename ${interface})"

cat >> "${IFFILE}" << EOF
allow-hotplug ${i}
iface ${i} inet ${method}

EOF

			done
		fi

		if [ ! -f /root/etc/resolv.conf ] || [ -z "$(cat /root/etc/resolv.conf)" ]
		then
			if [ -f /netboot.config ]
			then
				# create a resolv.conf if it is not present or empty
				cp /netboot.config /root/var/log/netboot.config

				rc_search=$(cat netboot.config | awk '/domain/ { print $3 }')
				rc_server0="$(cat netboot.config | awk '/dns0/ { print $5 }')"

cat > /root/etc/resolv.conf << EOF
search ${rc_search}
domain ${rc_search}
nameserver ${rc_server0}
EOF

				rc_server1=$(cat netboot.config | awk '/dns0/ { print $8 }')

				if [ "${rc_server1}" ! = "0.0.0.0" ]
				then
					echo "nameserver ${rc_server1}" >> /root/etc/resolv.conf
				fi

				cat /root/etc/resolv.conf >> /root/var/log/netboot.config
			fi
		fi
	fi

	log_end_msg
}
