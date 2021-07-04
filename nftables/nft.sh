#!/usr/bin/env bash
# Usage: bash <(curl -s https://raw.githubusercontent.com/mixool/across/master/nftables/nft.sh)
# Wiki: debian buster nftables https://wiki.archlinux.org/index.php/Nftables

# dependencies
command -v nft > /dev/null 2>&1 || { echo >&2 "Please install nftables： apt update && apt -t buster-backports install nftables -y"; exit 1; }

# nftables
cat <<EOF > /etc/nftables.conf
#!/usr/sbin/nft -f

flush ruleset

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
        
        tcp dport {http, https} counter accept
        udp dport {http, https} counter accept
        
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
