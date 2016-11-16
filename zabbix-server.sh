#!/bin/bash

#系统要求：mininal centos6.x
echo "a script to install zabbix-server on centos6.x"

read -p "zabbix_version:(default:3.2.1)" zabbix_version
if [[ -z $zabbix_version ]];then
zabbix_version=3.2.1
fi

read -p "nginx_version:(default:1.10.2)" nginx_version
if [[ -z $nginx_version ]];then
nginx_version=1.10.2
fi

read -p "php_version:(default:5.6.28)" php_version
if [[ -z $php_version ]];then
php_version=5.6.28
fi

yum groupinstall Development tools -y

present_dir=`pwd`
hostname=`hostname`
hostip=`ip a|grep inet |egrep -v "inet6|127.0.0.1"|cut -d" " -f6|cut -d/ -f1`
release=`cat /etc/centos-release |cut -d" " -f3|cut -d. -f1`

echo "system information:"
echo "hostname:$hostname"
echo "ip:$hostip"
echo "system-version:`cat /etc/centos-release`"
echo "zabbix_version:$zabbix_version"
echo "nginx_version:$nginx_version"
echo "php_version:$php_version"

read -p "are you sure ?(yes or no)" check
if [[ $check != yes ]];then
exit 0
fi

#关闭iptables和selinux
setenforce 0
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
service iptables stop
chkconfig iptables off

#安装mysql、php、nginx
yum install wget epel-release ntpdate mysql-server mysql-devel vixie-cron tar -y

#同步时间
echo "* */1 * * * /usr/sbin/ntpdate 133.100.11.8 >/dev/null" >> /var/spool/cron/root   

#配置zabbix数据库,默认版本yum源的5.1.73,之后看情况改进
echo -e "innodb_file_per_table = ON\nskip_name_resolve = ON" >> /etc/my.cnf
service mysqld start

read -p "mysql root password:(default:root)" mysql_root_passwd
if [[ -z $mysql_root_passwd ]];then
mysql_root_passwd=root
fi

mysqladmin  -uroot password "$mysql_root_passwd"
echo "create database zabbix default charset utf8;" | mysql -uroot -p$mysql_root_passwd
echo "grant all privileges on zabbix.* to zabbix@'localhost' identified by 'zabbix';" | mysql -uroot -p$mysql_root_passwd
echo "flush privileges;" | mysql -uroot -p$mysql_root_passwd

#安装nginx
cd $present_dir
wget http://nginx.org/download/nginx-$nginx_version.tar.gz
yum install pcre* openssl* -y
tar -xvf nginx-$nginx_version.tar.gz
cd nginx-$nginx_version
./configure --prefix=/usr/local/nginx --with-http_ssl_module --with-http_stub_status_module --with-pcre
make && make install

#安装php
cd $present_dir
wget http://cn2.php.net/distributions/php-$php_version.tar.gz
yum install gcc make gd-devel libjpeg-devel libpng-devel libxml2-devel bzip2-devel libcurl-devel -y
tar -xvf php-$php_version.tar.gz
cd php-$php_version
./configure --prefix=/usr/local/php --with-config-file-path=/usr/local/php/etc --with-bz2 --with-curl --enable-ftp --enable-sockets --disable-ipv6 --with-gd --with-jpeg-dir=/usr/local --with-png-dir=/usr/local --with-freetype-dir=/usr/local --enable-gd-native-ttf --with-iconv-dir=/usr/local --enable-mbstring --enable-calendar --with-gettext --with-libxml-dir=/usr/local --with-zlib --with-pdo-mysql=mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --enable-dom --enable-xml --enable-fpm --with-libdir=lib64 --enable-bcmath
make && make install

#配置php
cd $present_dir
cp php-$php_version/php.ini-production /usr/local/php/etc/php.ini
sed -i "s/max_execution_time = 30/max_execution_time = 300/g" /usr/local/php/etc/php.ini
sed -i "s/post_max_size = 8M/post_max_size = 16M/g" /usr/local/php/etc/php.ini
sed -i "s/max_input_time = 60/max_input_time = 300/g" /usr/local/php/etc/php.ini
sed -i "s/;date.timezone =/date.timezone = PRC/g" /usr/local/php/etc/php.ini
sed -i "s/;always_populate_raw_post_data = -1/always_populate_raw_post_data = -1/g" /usr/local/php/etc/php.ini
cp /usr/local/php/etc/php-fpm.conf.default /usr/local/php/etc/php-fpm.conf
cp php-$php_version/sapi/fpm/init.d.php-fpm /etc/init.d/php-fpm
chmod +x /etc/init.d/php-fpm

#编译安装zabbix服务端和客户端
cd $present_dir
wget http://nchc.dl.sourceforge.net/project/zabbix/ZABBIX%20Latest%20Stable/$zabbix_version/zabbix-$zabbix_version.tar.gz
yum install net-snmp-devel -y
tar -xvf zabbix-$zabbix_version.tar.gz
cd zabbix-$zabbix_version
./configure --prefix=/usr/local/zabbix --with-net-snmp --with-libcurl --enable-server --enable-agent --with-libxml2 --enable-agent --with-mysql
make && make install

#添加zabbix用户和组
groupadd zabbix
useradd -g zabbix -m zabbix

#配置zabbix数据库
/usr/bin/mysql -uroot -p$mysql_root_passwd zabbix < database/mysql/schema.sql
/usr/bin/mysql -uroot -p$mysql_root_passwd zabbix < database/mysql/images.sql 
/usr/bin/mysql -uroot -p$mysql_root_passwd zabbix < database/mysql/data.sql

#配置zabbix启动项
cp misc/init.d/tru64/zabbix_* /etc/init.d/
chmod +x /etc/init.d/zabbix_* 
sed -i "s@DAEMON=/usr/local/sbin/zabbix_server@DAEMON=/usr/local/zabbix/sbin/zabbix_server@g" /etc/init.d/zabbix_server
sed -i "s@DAEMON=/usr/local/sbin/zabbix_agentd@DAEMON=/usr/local/zabbix/sbin/zabbix_agentd@g" /etc/init.d/zabbix_agentd
sed -i "s/# DBPassword=/DBPassword=zabbix/g" /usr/local/zabbix/etc/zabbix_server.conf

#配置并启动nginx、php、zabbix
mkdir -p /usr/local/zabbix/web
cp -af $present_dir/zabbix-$zabbix_version/frontends/php/* /usr/local/zabbix/web
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


mv /usr/local/nginx/conf/nginx.conf /usr/local/nginx/conf/nginx.conf.bk
cat > /usr/local/nginx/conf/nginx.conf <<EOF
worker_processes  1;
events {
    worker_connections  1024;
       }
    http {
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

#启动各进程
/usr/local/nginx/sbin/nginx
service php-fpm start
service zabbix_server start
service zabbix_agentd start

echo "请打开浏览器输入http://$hostip来进行下一步配置，登录用户名为admin，密码为zabbix"
