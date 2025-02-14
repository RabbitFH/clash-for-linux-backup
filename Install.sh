# 安装Clash服务
export Server_Dir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
ln -s $Server_Dir/clash.service /etc/systemd/system/clash.service

# 重新加载systemctl配置
systemctl daemon-reload

# 启动Clash服务
systemctl start clash
systemctl enable clash