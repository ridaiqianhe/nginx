#!/bin/bash

# Function to get a valid domain or IP address
get_valid_domain() {
    while true; do
        read -p "请输入域名（不含http://）或有效IP地址: " domain
        if [[ $domain == *":"* ]]; then
            ip="${domain%:*}"
            port="${domain#*:}"
            if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && $port -ge 1 && $port -le 65535 ]]; then
                read -p "您输入的IP地址和端口为：$ip:$port，确认吗？(y/n): " confirm
                if [ "$confirm" = "y" ]; then
                    echo "$ip:$port"
                    return
                fi
            else
                echo "无效的IP地址或端口，请重新输入。"
            fi
        else
            read -p "您输入的域名为：$domain，确认吗？(y/n): " confirm
            if [ "$confirm" = "y" ]; then
                echo "$domain"
                return
            fi
        fi
    done
}

# Function to get the proxy domain
get_proxy_domain() {
    while true; do
        read -p "请输入反向代理的域名（带有http://或https://）: " proxy_domain
        if [[ $proxy_domain == http://* || $proxy_domain == https://* ]]; then
            read -p "您输入的反向代理域名为：$proxy_domain，确认吗？(y/n): " confirm
            if [ "$confirm" = "y" ]; then
                echo "$proxy_domain"
                return
            else
                echo "请重新输入反向代理域名。"
            fi
        else
            echo "请输入有效的反向代理域名（带有http或https）。"
        fi
    done
}

# Function to get load balancing option
get_load_balancing_option() {
    while true; do
        read -p "是否需要负载均衡？（y/n）: " option
        if [ "$option" = "y" ]; then
            proxy_domains=()
            while true; do
                read -p "请输入可用域名（输入空白值以停止输入）: " proxy_domain
                if [ -z "$proxy_domain" ]; then
                    if [ ${#proxy_domains[@]} -eq 0 ]; then
                        echo "请至少输入一个可用域名。"
                    else
                        read -p "您输入的可用域名为：${proxy_domains[*]}，确认吗？(y/n): " confirm
                        if [ "$confirm" = "y" ]; then
                            for domain in "${proxy_domains[@]}"; do
                                echo "$domain"
                            done
                            return
                        fi
                    fi
                else
                    proxy_domains+=("$proxy_domain")
                fi
            done
        elif [ "$option" = "n" ]; then
            return
        else
            echo "无效选项，请输入 'y' 或 'n'。"
        fi
    done
}

# Function to get cache time
get_cache_time() {
    while true; do
        read -p "请输入缓存时间（秒），如果不需要缓存请输入0: " cache_time
        if [[ $cache_time =~ ^[0-9]+$ && $cache_time -ge 0 && $cache_time -lt 10000000000 ]]; then
            echo "$cache_time"
            return
        else
            echo "缓存时间必须大于等于0且小于10的十次方。"
        fi
    done
}

# Main script
echo "欢迎使用Nginx反向代理配置脚本！"
domain_a=$(get_valid_domain)
proxy_domain=$(get_proxy_domain)
proxy_domains=$(get_load_balancing_option)
cache_time=$(get_cache_time)

# Create Nginx configuration
echo "worker_processes 1;" > nginx.conf
echo "events {" >> nginx.conf
echo "    worker_connections 1024;" >> nginx.conf
echo "}" >> nginx.conf
echo "" >> nginx.conf
echo "http {" >> nginx.conf
echo "    include /etc/nginx/mime.types;" >> nginx.conf
echo "    default_type application/octet-stream;" >> nginx.conf
echo "    sendfile on;" >> nginx.conf
echo "    keepalive_timeout 65;" >> nginx.conf
echo "    gzip on;" >> nginx.conf
echo "    server {" >> nginx.conf
echo "        listen 80;" >> nginx.conf
echo "        server_name $proxy_domain;" >> nginx.conf
echo "        location / {" >> nginx.conf
echo "            proxy_pass http://${proxy_domains[0]};" >> nginx.conf
echo "            proxy_next_upstream error timeout http_502;" >> nginx.conf
echo "            proxy_set_header Host $host;" >> nginx.conf
echo "            proxy_set_header X-Real-IP $remote_addr;" >> nginx.conf
echo "            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;" >> nginx.conf
echo "            proxy_set_header X-Forwarded-Proto $scheme;" >> nginx.conf
echo "            proxy_set_header X-Forwarded-Host $host;" >> nginx.conf
echo "            proxy_set_header X-Forwarded-Port $server_port;" >> nginx.conf
echo "            proxy_set_header X-Forwarded-Server $host;" >> nginx.conf
echo "            proxy_connect_timeout ${cache_time}s;" >> nginx.conf
echo "            proxy_send_timeout ${cache_time}s;" >> nginx.conf
echo "            proxy_read_timeout ${cache_time}s;" >> nginx.conf
echo "            proxy_cache_valid 200 304 ${cache_time}s;" >> nginx.conf
echo "        }" >> nginx.conf
echo "    }" >> nginx.conf
echo "}" >> nginx.conf

# Build Docker container
docker-compose up -d
echo "Nginx容器已创建并配置完成。"
