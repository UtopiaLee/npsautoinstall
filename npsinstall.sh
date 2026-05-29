#!/bin/bash
getos(){  
   local os_id=$(grep "^ID=" /etc/os-release | awk -F= '{print $2}' | tr -d '"')
   echo $os_id
}
basedomain=""
httpport=""
#获取Cpu的架构
getarch(){
     local arch=$(uname -m)
	 echo $arch
}

#安装Nginx
InstallNginx(){
   os=$(getos)
    case $os in
        "ubuntu" | "debian")
            # 在 Ubuntu 和 Debian 上安装 Nginx 的代码
			
            sudo apt-get update
            sudo apt-get install -y nginx
			sudo apt install lsof socat cron 
            ;;
        "centos" | "rhel" | "fedora")
            # 在 CentOS、RHEL 和 Fedora 上安装 Nginx 的代码
			sudo yum update 
            sudo yum install -y nginx
            ;;
        "opensuse" | "sles")
            # 在 openSUSE 和 SLES 上安装 Nginx 的代码
            sudo zypper install -y nginx
            ;;
        *)
            echo "Unsupported OS: $os"
            ;;
    esac
}

# 函数用于检查输入是否为数字
check_number() {
    local input=$1
    if [[ $input =~ ^[0-9]+$ ]]; then
        return 0  # 输入为数字
    else
        return 1  # 输入非数字
    fi
}

# 函数用于检查端口号的有效性
check_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]; then
        return 0  # 端口号有效
    else
        return 1  # 端口号无效
    fi
}

InstallNps(){
# 替换配置文件中的值
     uninstallNps
     echo "系统环境检测中"
	 os=$(getos)
	 arch=$(getarch)
	 echo "当前系统发行版是$os,CPU架构为$arch"
	 case "$arch" in
        "x86_64")
			echo "\033[0;33m开始下载Nps安装包\033[0;37m"
			wget  https://github.com/ehang-io/nps/releases/download/v0.26.10/linux_amd64_server.tar.gz
			tar -zvxf linux_amd64_server.tar.gz
            ;;
        "armv7l")
		   	echo "\033[0;33m开始下载Nps安装包\033[0;37m"
			wget https://github.com/ehang-io/nps/releases/download/v0.26.10/linux_arm_v7_server.tar.gz
			tar -zvxf linux_arm_v7_server.tar.gz
            ;;
        "aarch64")
		   	echo "\033[0;33m开始下载Nps安装包\033[0;37m"
			wget  https://github.com/ehang-io/nps/releases/download/v0.26.10/linux_arm64_server.tar.gz
			tar -zvxf linux_arm64_server.tar.gz
            ;;
        # 添加其他可能的架构
        *)
           echo "未知的架构: $arch"
           ;;
    esac
	UpdateConf
	./nps install
	nps start
	

}


UpdateConf(){
   
    config_file="conf/nps.conf"
	new_web_password="password.123"
    new_http_proxy_port="8010"
    new_https_proxy_port="8020"
   # 从用户那里获取新值
     read -r -p "请设置管理后台的密码(默认password.123): " temp_web_password
     new_web_password=${temp_web_password:-$new_web_password}  # 如果用户未提供有效输入，则使用默认值
     
     while true; do
        read -r  -p "请设置http代理端口(默认8010): " temp_http_proxy_port
		temp_http_proxy_port=${temp_http_proxy_port:-$new_http_proxy_port}
        if check_number "$temp_http_proxy_port" && check_port "$temp_http_proxy_port"; then
            new_http_proxy_port=$temp_http_proxy_port
			httpport=$temp_http_proxy_port
            break
        else
            echo "无效的端口号，请重新输入。"
        fi
    done

    # 读取并检查https代理端口输入
    while true; do
        read -r -p "请设置https的代理端口(默认8020): " temp_https_proxy_port
		  temp_https_proxy_port=${temp_https_proxy_port:-$new_https_proxy_port}
        if check_number "$temp_https_proxy_port" && check_port "$temp_https_proxy_port"; then
            new_https_proxy_port=$temp_https_proxy_port
			if [ "${new_http_proxy_port}" == "${new_https_proxy_port}" ];then
			  echo "http：${new_http_proxy_port}和https:${new_https_proxy_port}}端口重复"
			else
              break
			fi
        else
            echo "无效的端口号，请重新输入。"
        fi
		
		
    done
 sed -i "s/^web_password=.*/web_password=${new_web_password}/" "$config_file"
 sed -i "s/^http_proxy_port=.*/http_proxy_port=${new_http_proxy_port}/" "$config_file"
 sed -i "s/^https_proxy_port=.*/https_proxy_port=${new_https_proxy_port}/" "$config_file"
}

kill80(){
   port=80

# 使用lsof命令查找占用端口的进程
process_id=$(lsof -t -i :$port)

if [ -z "$process_id" ]; then
    echo "端口 $port 未被占用。"
else
    echo "占用端口 $port 的进程ID为 $process_id，正在终止该进程..."
    sudo kill -9 $process_id
    echo "进程已终止。"
fi

}

#独立80端口申请ssl证书
ApplyStandAlone(){
     curl https://get.acme.sh | sh
	  ~/.acme.sh/acme.sh  --upgrade  --auto-upgrade
	  randommail=$(mktemp -u XXXXXXXX@utopia.com)
	  ~/.acme.sh/acme.sh --register-account -m $randommail
	 
	 read -r -p "请输入你的域名:" userdoamin
	  # 仅获取域名的 IPv4 解析地址
      ip_address=$(nslookup -type=A "${userdoamin}" | awk '
        /^Name:/ {found=1}
        found && /^Address: / {print $2; exit}
      ')
	  basedomain=$userdoamin

     # 获取当前服务器IP地址
     ip_now=$(curl -4 -s ifconfig.me | tr -d '\r\n')
	 # 显示获取到的IP地址
    if [ -n "$ip_address" ] && [ -n "$ip_now" ]; then
      echo -e "\033[0;33m域名解析IP是: $ip_address，当前服务器IP是: $ip_now\033[0;37m"

     # 检查解析的IP是否与当前服务器IPv4一致
     if [ "$ip_address" != "$ip_now" ]; then
        echo -e "\033[0;33m解析域名不一致，请修改DNS解析\033[0;37m"
        return
      else
        echo -e "\033[0;32m解析域名一致\033[0;37m"
		echo "创建tls存放目录"
	    mkdir -p /usr/tls
        kill80
	    ~/.acme.sh/acme.sh --issue -d $userdoamin --standalone
		find ~/.acme.sh/ -name "${userdoamin}_ecc" -type d -exec cp -r {} /usr/tls/ \;
		AddNginxAlone
      fi
    else
      echo "无法获取目标主机的IPv4地址。"
	  Menu
   fi
}


#独立dns记录申请泛域名证书
ApplyDnsSLL(){
     curl https://get.acme.sh | sh
	 cd ~/.acme.sh
	 ./acme.sh  --upgrade  --auto-upgrade
	  randommail=$(mktemp -u XXXXXXXX@utopia.com)
	 ./acme.sh --register-account -m $randommail
	 
	 read -r -p "请输入你的域名:" userdoamin
	    mkdir -p /usr/tls
		basedomain=$userdoamin
		~/.acme.sh/acme.sh --issue --dns -d *.$userdoamin  -d $userdoamin --yes-I-know-dns-manual-mode-enough-go-ahead-please | tee dnsssl.log
	    log_file="dnsssl.log"
		cat -e $log_file
		domains=$(grep "Domain:" "$log_file" | sed -n "s/.*Domain: '\(.*\)'/\1/p")
		echo -e "\033[0;33m 需要添加的TXT记录: \n $domains  \033[0;37m"
        # 提取所有的 TXT 值
        txt_values=$(grep "TXT value:" "$log_file" | awk -F"'" '{print $2}' | awk '{print $1}')
		 echo -e "\033[0;33m 需要添加的TXT值: \n $txt_values \n \033[0;37m"
		while true;do 
		
		   chanlengedomain="_acme-challenge.$userdoamin" 
		   nslookup -type=TXT "$chanlengedomain" | tee nslookup.log
		   txt_records=$(nslookup -type=TXT "$chanlengedomain" | awk  '/^'"${chanlengedomain}"'/ {print $NF}' | tr -d '"')
		   echo -e "\033[0;33m 解析记录:$txt_records \n \033[0;37m"
		   read -r -p "按下Enter键检查Txt记录是否生效 强制生效(输入yes)" NO
		  if [ -n "$NO" ] && [ "$NO" == "yes" ]; then
            echo "用户输入yes"
            break
           fi
		   if [ "${txt_values[*]}" != "${txt_records[*]}" ]; then
		      echo -e "\033[0;33m 需要添加的TXT记录:$domains \n \033[0;37m"
		      echo -e "\033[0;33m 需要添加的TXT值:$txt_values \n \033[0;37m"
              echo -e "\033[0;33m 修改未生效 ，请检查是否添加为TXT记录(TXT记录可以重名) \033[0;37m"
			  echo -e "\033[0;33m ------------------------------------------------------- \033[0;37m"
           else
		     echo -e "\033[0;33m TxT记录已生效 \033[0;37m"
			 break
		   fi
		  done
	    ~/.acme.sh/acme.sh --renew --force -d *.$userdoamin  -d $userdoamin --yes-I-know-dns-manual-mode-enough-go-ahead-please
        find ~/.acme.sh/ -name "*.${userdoamin}_ecc" -type d -exec cp -r {} /usr/tls/ \;
		echo "生成的ssl证书已拷贝到/usr/tls目录下"
}

WildCardDomain(){
   InstallNginx
   uninstallNps
   InstallNps
   ApplyDnsSLL
   AddNginxConf

}

uninstallNps(){
   nps stop
   nps uninstall
   rm -Rf /etc/nps
   rm -Rf /usr/bin/nps /usr/local/bin/nps
}

AddNginxConf(){
    basedomain=${basedomain:-443}
	httpport=${httpport:-8010}
	rm -rf /etc/nginx/conf.d/
	mkdir -p /etc/nginx/conf.d/
    touch /etc/nginx/conf.d/${basedomain}.conf
    echo "server {
    listen 443 ssl;
    server_name 0.0.0.0;
    server_name [::];
	client_max_body_size 20M;
    ssl_certificate  /usr/tls/*.${basedomain}_ecc/*.${basedomain}.cer;
    ssl_certificate_key /usr/tls/*.${basedomain}_ecc/*.${basedomain}.key;
    ssl_session_timeout 5m;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    location / {
        proxy_set_header Host  \$http_host;
        proxy_pass http://127.0.0.1:${httpport};
	    proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
        proxy_send_timeout 30s;
	    proxy_set_header  Upgrade  \$http_upgrade;
        proxy_set_header  Connection \"\$connection_upgrade\";
    }
     
}
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}" > /etc/nginx/conf.d/${basedomain}.conf

 echo "server {
    listen       80;
    server_name  0.0.0.0;
    server_name [::];
    server_name _;

    location / {
         rewrite ^(.*)$ https://${host}$1 permanent;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}">/etc/nginx/conf.d/default.conf
echo "一条龙服务默认配置访问的是443端口，以及http会自动定向为https"
 kill80
 nginx
}

AddNginxAlone(){
    basedomain=${basedomain:-443}
	read -p "请输入你要代理的端口:" httpport
	httpport=${httpport:-8010}
	mkdir -p /etc/nginx/conf.d/
    touch /etc/nginx/conf.d/${basedomain}.conf
    echo "server {
    listen 443 ssl;
    server_name ${basedomain};
	client_max_body_size 20M;
    ssl_certificate  /usr/tls/${basedomain}_ecc/${basedomain}.cer;
    ssl_certificate_key /usr/tls/${basedomain}_ecc/${basedomain}.key;
    ssl_session_timeout 5m;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    location / {
        proxy_set_header Host  \$http_host;
        proxy_pass http://127.0.0.1:${httpport};
	    proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
        proxy_send_timeout 30s;
	    proxy_set_header  Upgrade  \$http_upgrade;
        proxy_set_header  Connection \"\$connection_upgrade\";
    }
     
}
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}" > /etc/nginx/conf.d/${basedomain}.conf
echo "Successed"
 nginx -s reload
}


applyByhandHttps(){
    read -p "请输入你的域名:" basedomain
    basedomain=${basedomain:-443}
	read -p "请输入你要代理的端口:" httpport
	httpport=${httpport:-8010}
	mkdir -p /etc/nginx/conf.d/
    touch /etc/nginx/conf.d/${basedomain}.conf
    echo "server {
    listen 443 ssl;
    server_name ${basedomain};
	client_max_body_size 20M;
    ssl_certificate  /usr/tls/${basedomain}_ecc/${basedomain}.cer;
    ssl_certificate_key /usr/tls/${basedomain}_ecc/${basedomain}.key;
    ssl_session_timeout 5m;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    location / {
        proxy_set_header Host  \$http_host;
        proxy_pass http://127.0.0.1:${httpport};
	    proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
        proxy_send_timeout 30s;
	    proxy_set_header  Upgrade  \$http_upgrade;
        proxy_set_header  Connection \"\$connection_upgrade\";
    }
     
}
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}" > /etc/nginx/conf.d/${basedomain}.conf

 echo "server {
    listen       80;
    server_name  0.0.0.0;
    server_name [::];
    server_name _;

    location / {
         rewrite ^(.*)$ https://${host}$1 permanent;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}">/etc/nginx/conf.d/default.conf

echo "Successed"
 nginx -s reload

}

applyByhandHttpsFan(){
    read -p "请输入你的泛域名:" basedomain
    basedomain=${basedomain:-443}
	read -p "请输入你要代理的端口:" httpport
	httpport=${httpport:-8010}
	mkdir -p /etc/nginx/conf.d/
    touch /etc/nginx/conf.d/${basedomain}.conf
    echo "server {
    listen 443 ssl;
    server_name ${basedomain};
	client_max_body_size 20M;
    ssl_certificate  /usr/tls/*.${basedomain}_ecc/*.${basedomain}.cer;
    ssl_certificate_key /usr/tls/*.${basedomain}_ecc/*.${basedomain}.key;
    ssl_session_timeout 5m;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    location / {
        proxy_set_header Host  \$http_host;
        proxy_pass http://127.0.0.1:${httpport};
	    proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
        proxy_send_timeout 30s;
	    proxy_set_header  Upgrade  \$http_upgrade;
        proxy_set_header  Connection \"\$connection_upgrade\";
    }
     
}
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}" > /etc/nginx/conf.d/${basedomain}.conf

 echo "server {
    listen       80;
    server_name  0.0.0.0;
    server_name [::];
    server_name _;

    location / {
         rewrite ^(.*)$ https://${host}$1 permanent;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}">/etc/nginx/conf.d/default.conf

echo "Successed"
 nginx -s reload

}
Menu(){
 status=true
 while $status;do
   echo -e  "\033[0;33m###################################\n"
   echo -e            "########Created By Utopia##########\n"
   echo -e  "################################### \033[0;31m\n"
   echo -e  "1.安装Nginx\n"
   echo -e  "2.安装Nps\n"
   echo -e  "3.申请SSL证书(80端口独占模式)\n"
   echo -e  "4.申请泛域名证书(dns修改所有权模式)\n"
   echo -e  "5.一键申请泛域名证书并且部署到Nginx反代Nps\n "
   echo -e  "6.卸载Nps \n"
   echo -e  "7.手动配置HtppsToNginx \n"
    echo -e  "8.手动配置HtppsToNginx(泛域名) \n"
   echo -e  "0.退出脚本 \033[0;37m\n"
   read -r -p "请选择:" userinput
   case "$userinput" in 
         "1")
		  InstallNginx
		  ;;
		  "2")
		   InstallNps
		  ;;
		  "3")
		   ApplyStandAlone
		  ;;
		  "4")
		  ApplyDnsSLL
		  ;;
		  "5")
		  WildCardDomain
		  ;;
		  "6")
		  echo "开始卸载Nps"
		  uninstallNps
		  ;;
		  "7")
		  applyByhandHttps
		  ;;
		  "8")
		  applyByhandHttpsFan
		  ;;
		  "0")
		  echo "exit 脚本"
		  status=false
		  ;;
		  *)
		  echo "没有这个选项"
		  ;;
    esac
  done
}


Menu
