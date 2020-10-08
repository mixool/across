#!/bin/sh
## 用于https://github.com/mixool/dockershc项目安装运行v2ray的脚本

if [[ "$(command -v workerone)" == "" ]]; then
    # install and rename
    wget -qO- https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip | busybox unzip - >/dev/null 2>&1
    cat <<EOF >/config.json
{
    "inbounds": 
    [
        {
            "port": 3000,"protocol": "vless",
            "settings": {"clients": [{"id": "dda17a0e-4c8e-4ed9-a9b3-9a03bbf684b8"}],"decryption": "none"},
            "streamSettings": {"network": "ws","wsSettings": {"path": "/vlesspath"}}
        }
    ],
    
    "outbounds": 
    [
        {"protocol": "freedom","tag": "direct","settings": {}},
        {"protocol": "blackhole","tag": "blocked","settings": {}}
    ],
    "routing": 
    {
        "rules": 
        [
            {"type": "field","outboundTag": "blocked","ip": ["geoip:private"]},
            {"type": "field","outboundTag": "block","protocol": ["bittorrent"]},
            {"type": "field","outboundTag": "blocked","domain": ["geosite:category-ads-all"]}
        ]
    }
}
EOF
    chmod +x /v2ray /v2ctl && mv /v2ray /usr/bin/workerone && /v2ctl config /config.json >/usr/bin/worker.pb >/dev/null 2>&1
    rm -rf /*.json /geo* /systemd/system/v2ray* /v2ctl /*.sig
else
    # start 
    workerone -config /usr/bin/worker.pb >/dev/null 2>&1
fi
