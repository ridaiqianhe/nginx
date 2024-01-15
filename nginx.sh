#!/bin/bash

# 函数：验证 IP 和端口
validate_ip_port() {
    if [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "输入了IP地址，需要输入端口。"
        read -p "请输入端口 [1-65535]: " port
        if ! [[ $port =~ ^[1-9][0-9]{0,4}$ ]] || [ $port -lt 1 ] || [ $port -gt 65535 ]; then
            echo "无效的端口号。"
            return 1
        fi
        proxy_domain="$1:$port"
    else
        proxy_domain=$1
    fi
    return 0
}

# 获取并验证代理域名 A
while true; do
    read -p "请输入代理域名 A: " domain_a
    validate_ip_port $domain_a
    if [ $? -eq 0 ]; then
        read -p "确认代理域名 A 是 $proxy_domain? [Y/n]: " confirm
        if [ "$confirm" != "n" ]; then
            break
        fi
    fi
done

# 确定是否需要负载均衡
read -p "是否需要负载均衡? [y/N]: " load_balancing
proxy_domains=()
if [ "$load_balancing" = "y" ]; then
    echo "输入反代域名，输入空白值结束。"
    while true; do
        read -p "输入反代域名: " domain
        if [ -z "$domain" ]; then
            break
        fi
        if ! [[ $domain =~ ^https?:// ]]; then
            echo "域名需要以 http 或 https 开头。"
        else
            proxy_domains+=($domain)
        fi
    done
else
    while true; do
        read -p "输入反代域名: " domain
        if [[ $domain =~ ^https?:// ]]; then
            proxy_domains+=($domain)
            break
        else
            echo "域名需要以 http 或 https 开头。"
        fi
    done
fi

# 获取并验证缓存时间 T
while true; do
    read -p "输入缓存时间（秒）: " cache_time
    if [[ $cache_time =~ ^[0-9]+$ ]] && [ $cache_time -ge 0 ] && [ $cache_time -le 10000000000 ]; then
        break
    else
        echo "无效的缓存时间。"
    fi
done

echo "创建 Docker 容器并配置 Nginx..."

container_name="nginx"

# 创建一个临时目录来存储 Nginx 配置文件
config_dir=/www/wwwroot

# 生成 Nginx 配置文件
cat > $config_dir/nginx.conf <<EOF
user  nginx;
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       80;
        server_name  $proxy_domain;

        location / {
            proxy_pass http://$domain_a;
            proxy_cache_bypass \$http_upgrade;

            # 设置缓存时间
            proxy_cache_valid 200 $cache_time;
        }

        # 如果需要负载均衡
        $(if [ "$load_balancing" = "y" ]; then
            echo "upstream backend {"
            for domain in "${proxy_domains[@]}"; do
                echo "    server $domain;"
            done
            echo "}"
          fi)
    }
}
EOF

# 启动 Docker 容器并挂载配置文件
docker run --name $container_name -v $config_dir/nginx.conf:/etc/nginx/nginx.conf:ro -d -p 80:80 nginx

# 清理配置文件
rm -rf $config_dir

echo "Nginx Docker 容器已启动。"
