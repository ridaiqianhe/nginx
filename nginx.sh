#!/bin/bash

start_enviroment() {
    if ! command -v docker &> /dev/null
    then
        echo "Docker 未安装，开始安装 Docker..."
        # 根据你的系统选择合适的安装命令
        # 这里以 Ubuntu 为例
        sudo apt update
        sudo apt install -y docker.io
        # 启动 Docker 服务
        sudo systemctl start docker
        # 设置 Docker 开机自启
        sudo systemctl enable docker
        echo "Docker 安装完成。"
    else
        echo "Docker 已安装。"
    fi

    read -p "是否删除所有含有 'nginx' 名字的容器? (y/N): " delete_option

    if [ "$delete_option" == "y" ]; then
        echo "正在查找并删除所有含有 'nginx' 名字的容器..."
        docker stop $(docker ps -a -q -f name=nginx)
        docker rm $(docker ps -a -q -f name=nginx)
        echo "所有含有 'nginx' 名字的容器已停止并删除。"
    else
        echo "未删除任何容器。以下是所有含有 'nginx' 名字的容器："
        docker ps -a --format "{{.Names}}" -f name=nginx
    fi

    echo "环境 OK!"
}

apply_certificate() {
    read -p "是否申请 SSL 证书? [y/N]: " apply_cert_option
    if [ "$apply_cert_option" = "y" ]; then
        if [ -s /$config_dir/tls/server.crt ] && [ -s /$config_dir/tls/server.key ]; then
            read -p "已存在证书文件，是否需要重新申请证书? [y/N]: " reapply_option
            if [ "$reapply_option" != "y" ]; then
                echo "用户取消重新申请 SSL 证书。"
                return
            fi
        fi

        echo "开始申请证书"
        apt update
        mkdir -p /$config_dir/tls
        chmod 777 /$config_dir/tls
        apt install cron curl socat -y
        curl https://get.acme.sh | sh
        ln -s  /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
        source ~/.bashrc
        acme.sh --set-default-ca --server letsencrypt
        acme.sh --issue -d $domain_a --standalone -k ec-256 --force
        acme.sh --installcert -d $domain_a --ecc  --key-file   /$config_dir/tls/server.key   --fullchain-file /$config_dir/tls/server.crt
        acme.sh --upgrade --auto-upgrade

        if test -s /$config_dir/tls/server.crt; then
            echo -e "证书申请成功!\n"
            echo -n "证书路径:"
            echo
            echo -e "/$config_dir/tls/server.crt"
            echo -e "/$config_dir/tls/server.key\n"
        else
            systemctl daemon-reload
            echo "证书安装失败！请检查原因！"
            exit
        fi
    else
        echo "用户取消申请 SSL 证书。"
    fi
}

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
load_domain(){ 
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
}

# 获取并验证代理域名
load_balancing() {
    # 确定是否需要负载均衡
    read -p "是否需要负载均衡? [y/N]: " load_balancing
    proxy_domains=()
    if [ "$load_balancing" = "y" ]; then
        echo "输入反代域名，输入空白值结束。无需http://"
        while true; do
            read -p "输入反代域名: " domain
            if [ -z "$domain" ]; then
                break
            fi
            proxy_domains+=($domain)
        done
    else
        while true; do
            read -p "输入反代地址: （例如：http://127.0.0.1:80）" domain
            if [[ $domain =~ ^https?:// ]]; then
                proxy_domains+=($domain)
                break
            else
                echo "域名需要以 http:// 或 https:// 开头。"
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
}
echo "创建 Docker 容器并配置 Nginx..."

make_conf() {
    cat > $config_dir/nginx.conf <<EOF
    user  nginx;
    worker_processes  1;

    events {
        worker_connections  1024;
    }

    http {
        sendfile        on;
        keepalive_timeout  65;

        $(if [ "$apply_cert_option" = "y" ]; then
            echo "ssl_certificate /etc/nginx/tls/server.crt;"
            echo "ssl_certificate_key /etc/nginx/tls/server.key;"
        fi)

        # 如果需要负载均衡
        $(if [ "$load_balancing" = "y" ]; then
            echo "upstream backend {"
            for domain in "${proxy_domains[@]}"; do
                echo "    server $domain;"
            done
            echo "}"
        fi)

        server {
            listen       80;
            $(if [ "$apply_cert_option" = "y" ]; then
                echo "listen 443 ssl;"
                echo "ssl_protocols TLSv1.2 TLSv1.3;"
                echo "ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';"
            fi)
            server_name  $proxy_domain;

            location / {
                $(if [ "$load_balancing" = "y" ]; then
                    echo "proxy_pass http://backend;"
                else
                    echo "proxy_pass $domain;"
                fi)
                proxy_cache_bypass \$http_upgrade;

                # 设置缓存时间
                proxy_cache_valid 200 $cache_time;
            }
        }
    }
EOF
}



#rm -rf $config_dir
start_enviroment
load_domain
container_name="nginx$domain_a"
config_dir=/www/wwwroot/nginx/$container_name
echo "$config_dir"
load_balancing
apply_certificate
make_conf

docker run --name $container_name \
    --restart=always \
    -v $config_dir/nginx.conf:/etc/nginx/nginx.conf \
    -v $config_dir/tls:/etc/nginx/tls \
    -d \
    --network host \
    nginx

echo "Nginx Docker 容器已启动。配置文件于 $config_dir/nginx.conf"
