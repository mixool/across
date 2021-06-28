#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin; export PATH

# tempfile & rm it when exit
trap 'rm -f "$TMPFILE"' EXIT; TMPFILE=$(mktemp) || exit 1

########
[[ $# != 1 ]] && [[ $# != 2 ]] && echo Err  !!! Useage: bash this_script.sh uuid my.domain.com && exit 1
[[ $# == 1 ]] && uuid="$(cat /proc/sys/kernel/random/uuid)" && domain="$1"
[[ $# == 2 ]] && uuid="$1" && domain="$2"
xtlsflow="xtls-rprx-direct" && ssmethod="none"
trojanpath="${uuid}-trojan"
vlesspath="${uuid}-vless"
vlessh2path="${uuid}-vlessh2"
vmesstcppath="${uuid}-vmesstcp"
vmesswspath="${uuid}-vmess"
vmessh2path="${uuid}-vmessh2"
shadowsockspath="${uuid}-ss"
configxray=${configxray:-https://raw.githubusercontent.com/mixool/across/master/xray/etc/xray.json}
configcaddy=${configcaddy:-https://raw.githubusercontent.com/mixool/across/master/xray/etc/caddy.json}
########

function install_xray_caddy(){
    # xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
    # caddy with layer4 cloudflare-dns forwardproxy: https://github.com/mixool/caddys
    caddyURL="$(wget -qO-  https://api.github.com/repos/caddyserver/caddy/releases | grep -E "browser_download_url.*linux_amd64\.deb" | cut -f4 -d\" | head -n1)"
    naivecaddyURL="https://github.com/mixool/caddys/raw/master/caddy"
    wget -O $TMPFILE $caddyURL && dpkg -i $TMPFILE
    rm -rf /usr/bin/caddy
    wget --no-check-certificate -O /usr/bin/caddy $naivecaddyURL && chmod +x /usr/bin/caddy
    sed -i "s/caddy\/Caddyfile$/caddy\/Caddyfile\.json/g" /lib/systemd/system/caddy.service && systemctl daemon-reload
}

function config_xray_caddy(){
    # xrayconfig
    wget -O /usr/local/etc/xray/config.json $configxray
    sed -i -e "s/\$uuid/$uuid/g" -e "s/\$xtlsflow/$xtlsflow/g" -e "s/\$ssmethod/$ssmethod/g" -e "s/\$trojanpath/$trojanpath/g" -e "s/\$vlesspath/$vlesspath/g" \
           -e "s/\$vlessh2path/$vlessh2path/g" -e "s/\$vmesstcppath/$vmesstcppath/g" -e "s/\$vmesswspath/$vmesswspath/g" -e "s/\$vmessh2path/$vmessh2path/g" \
           -e "s/\$shadowsockspath/$shadowsockspath/g" -e "s/\$domain/$domain/g" /usr/local/etc/xray/config.json
    # caddyconfig
    wget -qO- $configcaddy | sed -e "s/\$domain/$domain/g" -e "s/\$uuid/$uuid/g" -e "s/\$vlessh2path/$vlessh2path/g" -e "s/\$vmessh2path/$vmessh2path/g" >/etc/caddy/Caddyfile.json
}

function cert_acme(){
    apt install socat -y
    curl https://get.acme.sh | sh && source  ~/.bashrc
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    ~/.acme.sh/acme.sh --register-account -m my@example.com
    ~/.acme.sh/acme.sh --issue -d $domain --standalone --keylength ec-256 --pre-hook "systemctl stop caddy xray" --post-hook "~/.acme.sh/acme.sh --installcert -d $domain --ecc --fullchain-file /usr/local/etc/xray/$domain.crt --key-file /usr/local/etc/xray/$domain.key --reloadcmd \"systemctl restart caddy xray\""
    ~/.acme.sh/acme.sh --installcert -d $domain --ecc --fullchain-file /usr/local/etc/xray/$domain.crt --key-file /usr/local/etc/xray/$domain.key --reloadcmd "systemctl restart xray"
}

function start_info(){
    systemctl enable caddy xray && systemctl restart caddy xray && sleep 3 && systemctl status caddy xray | grep -A 2 "service"
    cat <<EOF >$TMPFILE
{
  "v": "2",
  "ps": "$domain-ws",
  "add": "$domain",
  "port": "443",
  "id": "$uuid",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "$domain",
  "path": "$vmesswspath",
  "tls": "tls"
}
EOF
vmesswsinfo="$(echo "vmess://$(base64 -w 0 $TMPFILE)")"

    cat <<EOF >$TMPFILE
{
  "v": "2",
  "ps": "$domain-h2",
  "add": "$domain",
  "port": "443",
  "id": "$uuid",
  "aid": "0",
  "net": "h2",
  "type": "none",
  "host": "$domain",
  "path": "$vmessh2path",
  "tls": "tls"
}
EOF
vmessh2info="$(echo "vmess://$(base64 -w 0 $TMPFILE)")"

    cat <<EOF >$TMPFILE
$(date) $domain vless:
uuid: $uuid
wspath: $vlesspath
h2path: $vlessh2path

$(date) $domain vmess:
uuid: $uuid
tcppath: $vmesstcppath
ws+tls: $vmesswsinfo
h2+tls: $vmessh2info

$(date) $domain trojan:
password: $uuid
path: $trojanpath
nowsLink: trojan://$uuid@$domain:443#$domain-trojan

$(date) $domain shadowsocks:   
ss://$(echo -n "${ssmethod}:${uuid}" | base64 | tr "\n" " " | sed s/[[:space:]]//g | tr -- "+/=" "-_ " | sed -e 's/ *$//g')@${domain}:443?plugin=v2ray-plugin%3Bpath%3D%2F${shadowsockspath}%3Bhost%3D${domain}%3Btls#${domain}

$(date) $domain naiveproxy:
probe_resistance: $uuid.com
proxy: https://$uuid:$uuid@$domain

$(date) Visit: https://$domain
EOF

    cat $TMPFILE | tee /var/log/${TMPFILE##*/} && echo && echo $(date) Info saved: /var/log/${TMPFILE##*/}
}

function remove_purge(){
    apt purge caddy -y
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
    bash <(curl https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --remove; systemctl disable v2ray
    ~/.acme.sh/acme.sh --uninstall
    return 0
}

function main(){
    [[ "$domain" == "remove_purge" ]] && remove_purge && exit 0
    install_xray_caddy
    config_xray_caddy
    cert_acme
    start_info
}

main