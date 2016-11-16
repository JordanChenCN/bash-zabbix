#!/bin/bash

#系统要求：mininal centos6.x
echo "a script to install zabbix-server on centos6.x"

#输入zabbix_server的ip和版本
read -p "zabbix_serverIP:" zabbix_serverIP
if [[ -z $zabbix_serverIP ]];then
echo "please enter the zabbix_serverIP"
fi

read -p "zabbix_version:(default:3.2.1)" zabbix_version
if [[ -z $zabbix_version ]];then
zabbix_version=3.2.1
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

read -p "are you sure ?(yes or no)" check
if [[ $check != yes ]];then
exit 0
fi

#关闭iptables和selinux
setenforce 0
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
service iptables stop
chkconfig iptables off

#安装一些基础命令和依赖
yum install wget epel-release ntpdate vixie-cron tar -y

#同步时间
echo "* */1 * * * /usr/sbin/ntpdate 133.100.11.8 >/dev/null" >> /var/spool/cron/root 

#编译安装zabbix_agent
cd $present_dir
wget http://$zabbix_serverIP/zabbix-$zabbix_version.tar.gz
tar -xvf zabbix-$zabbix_version.tar.gz
cd zabbix-$zabbix_version
./configure --prefix=/usr/local/zabbix --enable-agent
make && make install

#配置zabbix_agent
cp misc/init.d/tru64/zabbix_agentd /etc/init.d/
chmod +x /etc/init.d/zabbix_agentd
sed -i "s@DAEMON=/usr/local/sbin/zabbix_agentd@DAEMON=/usr/local/zabbix/sbin/zabbix_agentd@g" /etc/init.d/zabbix_agentd
sed -i "s/Server=127.0.0.1/Server=$zabbix_serverIP/g" /usr/local/zabbix/etc/zabbix_agentd.conf
sed -i "s/ServerActive=127.0.0.1/ServerActive=$zabbix_serverIP/g" /usr/local/zabbix/etc/zabbix_agentd.conf
sed -i "s/Hostname=Zabbix server/Hostname=$hostname/g" /usr/local/zabbix/etc/zabbix_agentd.conf

#添加zabbix用户和组
groupadd zabbix
useradd -g zabbix -m zabbix

#启动zabbix_agentd
service zabbix_agentd start

echo "请在浏览器输入http://$zabbix_serverIP配置客户端"
