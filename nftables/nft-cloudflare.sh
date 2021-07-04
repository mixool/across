#!/usr/bin/env bash
# Usage: bash <(curl -s https://raw.githubusercontent.com/mixool/across/master/nftables/nft-cloudflare.sh)
# Wiki: debian buster nftables https://wiki.archlinux.org/index.php/Nftables

# dependencies
command -v nft > /dev/null 2>&1 || { echo >&2 "Please install nftables： apt update && apt -t buster-backports install nftables -y"; exit 1; }

# nftables
cat <<EOF > /etc/nftables.conf
#!/usr/sbin/nft -f

flush ruleset

# List all IPs and IP ranges of your traffic filtering proxy source. https://www.cloudflare.com/ips/
define SAFE_TRAFFIC_IPS = {
    173.245.48.0/20,
    103.21.244.0/22,
    103.22.200.0/22,
    103.31.4.0/22,
    141.101.64.0/18,
    108.162.192.0/18,
    190.93.240.0/20,
    188.114.96.0/20,
    197.234.240.0/22,
    198.41.128.0/17,
    162.158.0.0/15,
    104.16.0.0/12,
    172.64.0.0/13,
    131.0.72.0/22
}

table inet my_table {
    set blackhole {
        type ipv4_addr
        size 65535
        flags dynamic,timeout
        timeout 1d
    }
    
    chain my_input {
        type filter hook input priority 0;
        
        iif lo accept
        ip saddr @blackhole counter set update ip saddr @blackhole counter drop  
        
        icmp type echo-request limit rate over 1/second counter drop
        icmp type echo-request counter accept
        icmpv6 type {echo-request, nd-neighbor-solicit} limit rate over 1/second counter drop
        icmpv6 type {echo-request, nd-neighbor-solicit} counter accept
        
        ct state {established, related} counter accept
        ct state invalid counter drop
        
        tcp dport { http, https } ip saddr \$SAFE_TRAFFIC_IPS counter accept
        udp dport { http, https } ip saddr \$SAFE_TRAFFIC_IPS counter accept
        
        tcp flags syn tcp dport $(cat /etc/ssh/sshd_config | grep -oE "^Port [0-9]*$" | grep -oE "[0-9]*" || echo 22) meter aaameter { ip saddr ct count over 20 } add @blackhole { ip saddr } counter drop
        tcp flags syn tcp dport $(cat /etc/ssh/sshd_config | grep -oE "^Port [0-9]*$" | grep -oE "[0-9]*" || echo 22) meter bbbmeter { ip saddr limit rate over 20/hour } add @blackhole { ip saddr } counter drop
        tcp dport $(cat /etc/ssh/sshd_config | grep -oE "^Port [0-9]*$" | grep -oE "[0-9]*" || echo 22) ct state new limit rate 20/minute counter accept
        
        counter drop
    }
    
    chain my_forward {
        type filter hook forward priority 0;
        ip daddr @blackhole counter reject
        counter accept
    }
    
    chain my_output {
        type filter hook output priority 0;
        ip daddr @blackhole counter reject
        counter accept
    }
}
EOF

systemctl enable nftables && systemctl restart nftables && systemctl status nftables && nft list ruleset