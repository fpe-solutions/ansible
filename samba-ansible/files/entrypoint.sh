#!/bin/bash
set -e

SAMBA_REALM=${SAMBA_REALM:-"FPE.LOCAL"}
SAMBA_DOMAIN=${SAMBA_DOMAIN:-"FPE"}
SAMBA_ADMIN_PASSWORD=${SAMBA_ADMIN_PASSWORD:-"Admin@12345"}
SAMBA_DNS_FORWARDER=${SAMBA_DNS_FORWARDER:-"8.8.8.8"}

# IP واقعی سرور روی شبکه LAN
SAMBA_LAN_IP=${SAMBA_LAN_IP:-"192.168.107.160"}

# نام DC / hostname
SAMBA_HOSTNAME=${SAMBA_HOSTNAME:-"fpe-samba"}

# DNS zone با حروف کوچک
SAMBA_DNS_ZONE=${SAMBA_DNS_ZONE:-"fpe.local"}

if [ ! -f /var/lib/samba/private/krb5.conf ]; then

	    rm -f /etc/samba/smb.conf

	        samba-tool domain provision \
			        --server-role=dc \
				        --use-rfc2307 \
					        --dns-backend=SAMBA_INTERNAL \
						        --realm="${SAMBA_REALM}" \
							        --domain="${SAMBA_DOMAIN}" \
								        --host-name="${SAMBA_HOSTNAME}" \
									        --adminpass="${SAMBA_ADMIN_PASSWORD}" \
										        --option="interfaces=lo ${SAMBA_LAN_IP}" \
											        --option="bind interfaces only=yes"

		    # اطمینان از تنظیم DNS forwarder
		        sed -i "/\[global\]/a\\\tdns forwarder = ${SAMBA_DNS_FORWARDER}" /etc/samba/smb.conf

			    # اطمینان از bind شدن فقط روی IP دست
			        if ! grep -q "^interfaces =" /etc/samba/smb.conf; then
					        sed -i "/\[global\]/a\\\tinterfaces = lo ${SAMBA_LAN_IP}" /etc/samba/smb.conf
						    else
							            sed -i "s|^interfaces =.*|interfaces = lo ${SAMBA_LAN_IP}|" /etc/samba/smb.conf
								        fi

									    if ! grep -q "^bind interfaces only =" /etc/samba/smb.conf; then
										            sed -i "/\[global\]/a\\\tbind interfaces only = yes" /etc/samba/smb.conf
											        else
													        sed -i "s|^bind interfaces only =.*|bind interfaces only = yes|" /etc/samba/smb.conf
														    fi

														        cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

															    # Create share folders
															        mkdir -p /shares/public
																    mkdir -p /shares/fpe_group

																        chmod 777 /shares/public
																	    chmod 770 /shares/fpe_group

																	        # Add shares to smb.conf
																		    cat <<EOF >> /etc/samba/smb.conf
																		    [Public-Share]
																		       path = /shares/public
																		          browsable = yes
   read only = no
   guest ok = yes

[FPE-Only]
   path = /shares/fpe_group
   browsable = yes
   read only = no
   valid users = @FPE

EOF

    echo "[INFO] Starting temporary Samba for DNS cleanup..."

    samba --foreground --no-process-group &
        SAMBA_PID=$!

	    echo "[INFO] Waiting for Samba DNS to become ready..."
	        sleep 10

		    echo "[INFO] Cleaning wrong Docker DNS records..."

		        # حذف رکوردهای اشتبه دامنه اصلی
			    samba-tool dns delete 127.0.0.1 "${SAMBA_DNS_ZONE}" @ A 172.17.0.1 -U "Administrator%${SAMBA_ADMIN_PASSWORD}" || true
			        samba-tool dns delete 127.0.0.1 "${SAMBA_DNS_ZONE}" @ A 172.19.0.1 -U "Administrator%${SAMBA_ADMIN_PASSWORD}" || true

				    # حذف رکوردهای اشتباه hostname خود DC
				        samba-tool dns delete 127.0.0.1 "${SAMBA_DNS_ZONE}" "${SAMBA_HOSTNAME}" A 172.17.0.1 -U "Administrator%${SAMBA_ADMIN_PASSWORD}" || true
					    samba-tool dns delete 127.0.0.1 "${SAMBA_DNS_ZONE}" "${SAMBA_HOSTNAME}" A 172.19.0.1 -U "Administrator%${SAMBA_ADMIN_PASSWORD}" || true

					        # اطمینان از وجود رکورد درست
						    samba-tool dns add 127.0.0.1 "${SAMBA_DNS_ZONE}" @ A "${SAMBA_LAN_IP}" -U "Administrator%${SAMBA_ADMIN_PASSWORD}" || true
						        samba-tool dns add 127.0.0.1 "${SAMBA_DNS_ZONE}" "${SAMBA_HOSTNAME}" A "${SAMBA_LAN_IP}" -U "Administrator%${SAMBA_ADMIN_PASSWORD}" || true

							    echo "[INFO] DNS records after cleanup:"
							        samba-tool dns query 127.0.0.1 "${SAMBA_DNS_ZONE}" @ ALL -U "Administrator%${SAMBA_ADMIN_PASSWORD}" || true
								    samba-tool dns query 127.0.0.1 "${SAMBA_DNS_ZONE}" "${SAMBA_HOSTNAME}" ALL -U "Administrator%${SAMBA_ADMIN_PASSWORD}" || true

								        echo "[INFO] Stopping temporary Samba..."
									    kill "${SAMBA_PID}" || true
									        sleep 3

fi

if [ ! -f /etc/krb5.conf ] && [ -f /var/lib/samba/private/krb5.conf ]; then
	    cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
fi

echo "[INFO] Starting Samba AD DC..."
exec samba --foreground --no-process-group

