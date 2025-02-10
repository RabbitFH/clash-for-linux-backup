#!/bin/bash

# 关闭系统代理
source /etc/profile.d/clash.sh
proxy_off

sleep 1

# 关闭clash服务
PID_NUM=`ps -ef | grep [c]lash-linux-a | wc -l`
PID=`ps -ef | grep [c]lash-linux-a | awk '{print $2}'`
if [ $PID_NUM -ne 0 ]; then
	kill -9 $PID
	# ps -ef | grep [c]lash-linux-a | awk '{print $2}' | xargs kill -9
fi

# 清除环境变量
> /etc/profile.d/clash.sh
echo -e "\n环境变量卸载完成\\033[60G[\\033[1;31m  OK  \\033[0;39m]"
echo -e "\n服务关闭成功\\033[60G[\\033[1;31m  OK  \\033[0;39m]"
echo -e "\n\n"