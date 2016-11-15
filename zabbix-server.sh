#/bin/bash

#系统要求：mininal centos6.5
echo "a quck script to install zabbix-server on centos6.5"

zabbix_version=3.2.1
read -p "zabbix_dir:"  zabbix_dir   #需要交互输入zabbix的目录
#zabbix_dir=$1                      #不需要交互输入zabbix的目录
present_dir=`pwd`
hostname=`hostname`
hostip=`ip a|grep inet |egrep -v "inet6|127.0.0.1"|cut -d" " -f6|cut -d/ -f1`
release=`cat /etc/centos-release |cut -d" " -f3|cut -d. -f1`

echo "system information:"
echo "hostname:$hostname"
echo "ip:$hostip"
echo "system-version:`cat /etc/centos-release`"


#关闭iptables和selinux

if [ $release = 6 ];then
setenforce 0
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config

service iptables stop
chkconfig iptables off




#安装mysql、php、nginx
yum install wget epel-release ntpdate mysql-server mysql-devel -y

#同步时间
echo "* */1 * * * /usr/sbin/ntpdate 192.168.83.83 >/dev/null" >> /var/spool/cron/root   

#配置zabbix数据库
echo -e "innodb_file_per_table = ON\nskip_name_resolve = ON" >> /etc/my.cnf
service mysqld start
mysqladmin  -uroot password "root"
echo "create database zabbix default charset utf8;" | mysql -uroot -proot
echo "grant all privileges on zabbix.* to zabbix@'localhost' identified by 'zabbix';" | mysql -uroot -proot
echo "flush privileges;" | mysql -uroot -proot


#安装nginx
cd $present_dir
wget http://nginx.org/download/nginx-1.10.2.tar.gz
yum install pcre* openssl* -y
tar -xvf nginx-1.10.2.tar.gz
cd nginx-1.10.2
./configure --prefix=/usr/local/nginx --with-http_ssl_module --with-http_stub_status_module --with-pcre
make && make install

#安装php
cd $present_dir
wget http://cn2.php.net/distributions/php-5.6.28.tar.gz
yum install gcc make gd-devel libjpeg-devel libpng-devel libxml2-devel bzip2-devel libcurl-devel -y
tar -xvf cd php-5.6.28.tar.gz
cd php-5.6.2
./configure --prefix=/usr/local/php --with-config-file-path=/usr/local/php/etc --with-bz2 --with-curl --enable-ftp --enable-sockets --disable-ipv6 --with-gd --with-jpeg-dir=/usr/local --with-png-dir=/usr/local --with-freetype-dir=/usr/local --enable-gd-native-ttf --with-iconv-dir=/usr/local --enable-mbstring --enable-calendar --with-gettext --with-libxml-dir=/usr/local --with-zlib --with-pdo-mysql=mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --enable-dom --enable-xml --enable-fpm --with-libdir=lib64 --enable-bcmath
make && make install

#配置php
cd $present_dir
cp php-5.6.28/php.ini-production /usr/local/php/etc/php.ini
sed -i "s/max_execution_time = 30/max_execution_time = 300/g" /usr/local/php/etc/php.ini
sed -i "s/post_max_size = 8M/post_max_size = 16M/g" /usr/local/php/etc/php.ini
sed -i "s/max_input_time = 60/max_input_time = 300/g" /usr/local/php/etc/php.ini
sed -i "s/;date.timezone =/date.timezone = RPC/g" /usr/local/php/etc/php.ini
sed -i "s/;always_populate_raw_post_data = -1/always_populate_raw_post_data = -1/g" /usr/local/php/etc/php.ini
cp /usr/local/php/etc/php-fpm.conf.default /usr/local/php/etc/php-fpm.conf

#编译安装zabbix服务端和客户端
cd $present_dir
wget http://nchc.dl.sourceforge.net/project/zabbix/ZABBIX%20Latest%20Stable/3.2.1/zabbix-3.2.1.tar.gz
yum install net-snmp-devel -y
tar -xvf zabbix-3.2.1.tar.gz
cd zabbix-3.2.1
./configure --prefix=/usr/local/zabbix --with-net-snmp --with-libcurl --enable-server --enable-agent --with-libxml2 --enable-agent --with-mysql
make && make install

#添加zabbix用户和组
groupadd zabbix
useradd -g zabbix -m zabbix

#配置zabbix数据库
/usr/bin/mysql -uroot -proot zabbix < database/mysql/schema.sql
/usr/bin/mysql -uroot -proot zabbix < database/mysql/images.sql 
/usr/bin/mysql -uroot -proot zabbix < database/mysql/data.sql

#配置zabbix启动项
cp misc/init.d/tru64/zabbix_* /etc/init.d/
chmod +x /etc/init.d/zabbix_* 
sed -i "s@DAEMON=/usr/local/sbin/zabbix_server@DAEMON=/usr/local/zabbix/sbin/zabbix_server@g" /etc/init.d/zabbix_server
sed -i "s@DAEMON=/usr/local/sbin/zabbix_agentd@DAEMON=/usr/local/zabbix/sbin/zabbix_agentd@g" /etc/init.d/zabbix_agentd
sed -i "s/# DBPassword=/DBPassword=zabbix/g" /usr/local/zabbix/etc/zabbix_server.conf

#配置并启动nginx、php、zabbix
mkdir -p /usr/local/zabbix/web
cp -af $present_dir/zabbix-3.2.1/frontends/php/* /usr/local/zabbix/web
cat > /usr/local/zabbix/web/conf/zabbix.conf.php <<EOF
<?php
// Zabbix GUI configuration file.
global \$DB;

\$DB['TYPE']     = 'MYSQL';
\$DB['SERVER']   = '127.0.0.1';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER']     = 'zabbix';
\$DB['PASSWORD'] = 'zabbix';

// Schema name. Used for IBM DB2 and PostgreSQL.
\$DB['SCHEMA'] = '';

\$ZBX_SERVER      = 'localhost';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = '';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
EOF


mv /usr/loca/nginx/conf/nginx.conf /usr/loca/nginx/conf/nginx.conf.bk
cat > /usr/local/nginx/conf/nginx.conf <<EOF
worker_processes  1;
events {
    worker_connections  1024;
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    server {
        listen       80;
        server_name  zabbix server;
        root /usr/local/zabbix/web/;
        index  index.php index.html index.htm;
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
                location /
                        {
                                try_files \$uri \$uri/ /index.php?\$args;
                        }
                location ~ .*\\.(php)?$
                        {
                                expires -1s;
                                try_files \$uri =404;
                                fastcgi_split_path_info ^(.+\\.php)(/.+)$;
                                include fastcgi_params;
                                fastcgi_param PATH_INFO \$fastcgi_path_info;
                                fastcgi_index index.php;
                                fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                                fastcgi_pass 127.0.0.1:9000;
                        }
    }
}
EOF


/usr/local/nginx/sbin/nginx
/usr/local/php/sbin/php-fpm
service zabbix_server start
service zabbix_agentd start

echo "请打开浏览器输入http://$ip来进行下一步安装，用户名为admin，密码为zabbix"



