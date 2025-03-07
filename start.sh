#!/bin/bash

# 加载系统函数库(Only for RHEL Linux)
# [ -f /etc/init.d/functions ] && source /etc/init.d/functions

#################### 脚本初始化任务 ####################

# 获取脚本工作目录绝对路径
export Server_Dir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)

# 加载.env变量文件
source $Server_Dir/.env

# 给二进制启动程序、脚本等添加可执行权限
chmod +x $Server_Dir/bin/*
chmod +x $Server_Dir/scripts/*
chmod +x $Server_Dir/tools/subconverter/subconverter



#################### 变量设置 ####################

Conf_Dir="$Server_Dir/conf"
Temp_Dir="$Server_Dir/temp"
Log_Dir="$Server_Dir/logs"

# 将 CLASH_URL 变量的值赋给 URL 变量，并检查 CLASH_URL 是否为空
URL=${CLASH_URL:?Error: CLASH_URL variable is not set or empty}

# 获取 CLASH_SECRET 值，如果不存在则生成一个随机数
Secret=${CLASH_SECRET:-$(openssl rand -hex 32)}

# 获取 CLASH_UI 值，如果不存在则设置默认值
Dashboard_Dir=${CLASH_UI:Clash}

#################### 函数定义 ####################

# 自定义action函数，实现通用action功能
success() {
	echo -en "\\033[60G[\\033[1;32m  OK  \\033[0;39m]\r"
	return 0
}

failure() {
	local rc=$?
	echo -en "\\033[60G[\\033[1;31mFAILED\\033[0;39m]\r"
	[ -x /bin/plymouth ] && /bin/plymouth --details
	return $rc
}

action() {
	local STRING rc

	STRING=$1
	echo -n "$STRING "
	shift
	"$@" && success $"$STRING" || failure $"$STRING"
	rc=$?
	echo
	return $rc
}

# 判断命令是否正常执行 函数
if_success() {
	local ReturnStatus=$3
	if [ $ReturnStatus -eq 0 ]; then
		action "$1" /bin/true
	else
		action "$2" /bin/false
		exit 1
	fi
}



#################### 任务执行 ####################

## 获取CPU架构信息
# Source the script to get CPU architecture
source $Server_Dir/scripts/get_cpu_arch.sh

# Check if we obtained CPU architecture
if [[ -z "$CpuArch" ]]; then
	echo "Failed to obtain CPU architecture"
	exit 1
fi

export CpuArch=$CpuArch


## 临时取消环境变量
unset http_proxy
unset https_proxy
unset all_proxy
unset no_proxy
unset HTTP_PROXY
unset HTTPS_PROXY
unset ALL_PROXY
unset NO_PROXY


## Clash 订阅地址检测及配置文件下载
# 检查url是否有效
echo -e '\n正在检测订阅地址...'
Text1="Clash订阅地址可访问！"
Text2="Clash订阅地址不可访问！"
#curl -o /dev/null -s -m 10 --connect-timeout 10 -w %{http_code} $URL | grep '[23][0-9][0-9]' &>/dev/null
curl -o /dev/null -L -k -sS --retry 5 -m 10 --connect-timeout 10 -w "%{http_code}" $URL | grep -E '^[23][0-9]{2}$' &>/dev/null
ReturnStatus=$?
if_success $Text1 $Text2 $ReturnStatus

# 拉取更新config.yml文件
echo -e '\n正在下载Clash配置文件...'
Text3="配置文件config.yaml下载成功！"
Text4="配置文件config.yaml下载失败，退出启动！"

# 尝试使用curl进行下载
curl -L -k -sS --retry 5 -m 10 -o $Temp_Dir/clash.yaml $URL
ReturnStatus=$?
if [ $ReturnStatus -ne 0 ]; then
	# 如果使用curl下载失败，尝试使用wget进行下载
	for i in {1..10}
	do
		wget -q --no-check-certificate -O $Temp_Dir/clash.yaml $URL
		ReturnStatus=$?
		if [ $ReturnStatus -eq 0 ]; then
			break
		else
			continue
		fi
	done
fi
if_success $Text3 $Text4 $ReturnStatus

# 重命名clash配置文件
\cp -a $Temp_Dir/clash.yaml $Temp_Dir/clash_config.yaml


## 判断订阅内容是否符合clash配置文件标准，尝试转换（当前不支持对 x86_64 以外的CPU架构服务器进行clash配置文件检测和转换，此功能将在后续添加）
if [[ $CpuArch =~ "x86_64" || $CpuArch =~ "amd64" || $CpuArch =~ "arm64" ]]; then
	echo -e '\n判断订阅内容是否符合clash配置文件标准:'
	bash $Server_Dir/scripts/clash_profile_conversion.sh
	sleep 3
fi


## Clash 配置文件重新格式化及配置
# 取出代理相关配置 
#sed -n '/^proxies:/,$p' $Temp_Dir/clash.yaml > $Temp_Dir/proxy.txt
sed -n '/^proxies:/,$p' $Temp_Dir/clash_config.yaml |\
sed -e '/^port:/d'\
    -e '/^socks-port:/d'\
    -e '/^redir-port:/d'\
    -e '/^tproxy-port:/d'\
    -e '/^mixed-port:/d'\
    -e '/^allow-lan"/d'\
    -e '/^bind-address"/d'\
    -e '/^mode:/d'\
    -e '/^log-level:/d'\
    -e '/^external-controller:/d'\
    -e '/^external-ui:/d'\
    -e '/^secret:/d'\
    -e '/^interface-name:/d'\
    -e '/^routing-mark:/d' > $Temp_Dir/proxy.txt

# 合并形成新的config.yaml
cat $Temp_Dir/templete_config.yaml > $Temp_Dir/config.yaml
echo -e "\n\n" >> $Temp_Dir/config.yaml
cat $Temp_Dir/proxy.txt >> $Temp_Dir/config.yaml
echo -e "\n\n" >> $Temp_Dir/config.yaml
cat $Temp_Dir/templete_tun.yaml >> $Temp_Dir/config.yaml
\cp $Temp_Dir/config.yaml $Conf_Dir/

# Configure Clash Dashboard
Work_Dir=$(cd $(dirname $0); pwd)
Dashboard_Dir="${Work_Dir}/dashboard/${Dashboard_Dir}"
sed -ri "s@^# external-ui:.*@external-ui: ${Dashboard_Dir}@g" $Conf_Dir/config.yaml
sed -ri '/^secret: /s@(secret: ).*@\1'${Secret}'@g' $Conf_Dir/config.yaml


## 启动Clash服务
# 获取程序路径
Exec_Dir=$Server_Dir
if [[ $CpuArch =~ "x86_64" || $CpuArch =~ "amd64"  ]]; then
	Exec_Dir=$Exec_Dir/bin/clash-linux-amd64
elif [[ $CpuArch =~ "aarch64" ||  $CpuArch =~ "arm64" ]]; then
	Exec_Dir=$Exec_Dir/bin/clash-linux-arm64
elif [[ $CpuArch =~ "armv7" ]]; then
	Exec_Dir=$Exec_Dir/bin/clash-linux-armv7
else
	echo -e "\033[31m\n[ERROR] Unsupported CPU Architecture！\033[0m"
	exit 1
fi

# 作为服务启动则不使用后台运行
echo -e '\n正在启动Clash服务...'
Text5="服务启动成功！"
Text6="服务启动失败！"
Log_File="$Log_Dir/$(date +"%Y-%m-%d-%H%M%S").log"
if systemctl is-active --quiet clash; then
	echo -e "服务运行................................"
	$Exec_Dir -d $Conf_Dir > $Log_File
	Error_Message=$(tail -n 1 $Log_File | sed -n 's/.*msg="\([^"]*\)".*/\1/p')
	[ -z "$Error_Message" ] && Error_Message="未找到错误信息，请查看日志文件！"
	echo -e "\033[31m\n[ERROR]$Text6\n[ERROR]Message：“$Error_Message“\033[0m"
	systemctl stop clash
	exit 1
else
	nohup $Exec_Dir -d $Conf_Dir &> $Log_File &
	ReturnStatus=$?
	if_success $Text5 $Text6 $ReturnStatus
fi

# Output Dashboard access address and Secret
UI_Prot=$(sed -n '/external-controller:/s/.*:\([0-9]*\).*/\1/p' $Conf_Dir/config.yaml)
echo -e "\nClash Dashboard 访问地址: http://<ip>:$UI_Prot/ui"
echo -e "Secret: ${Secret}"

# 添加环境变量(root权限)
cat>/etc/profile.d/clash.sh<<EOF
# 开启系统代理
proxy_on() {
	export http_proxy=http://127.0.0.1:7890
	export https_proxy=http://127.0.0.1:7890
	export all_proxy="socks5://127.0.0.1:7890"
	export no_proxy=127.0.0.1,localhost
    export HTTP_PROXY=http://127.0.0.1:7890
    export HTTPS_PROXY=http://127.0.0.1:7890
    export ALL_PROXY="socks5://127.0.0.1:7890"
 	export NO_PROXY=127.0.0.1,localhost
	echo -e "\033[32m[√] 已开启代理\033[0m"
}

# 关闭系统代理
proxy_off(){
	unset http_proxy
	unset https_proxy
  	unset all_proxy
	unset no_proxy
  	unset HTTP_PROXY
	unset HTTPS_PROXY
  	unset ALL_PROXY
	unset NO_PROXY
	echo -e "\033[31m[×] 已关闭代理\033[0m"
}
EOF

# 加载环境变量
source /etc/profile.d/clash.sh
echo -e "\n环境变量加载完成\\033[60G[\\033[1;32m  OK  \\033[0;39m]"

# 开启系统代理
proxy_on

# 检查端口
sleep 3
echo ""
echo -e "====================检查端口状态===================="
netstat -tln | grep -E $UI_Prot'|53|789.'
echo -e "==================================================="
echo ""

echo -e "#####################可用命令集#####################"
echo -e "#### 开启代理: \033[32mproxy_on\033[0m"
echo -e "#### 关闭代理: \033[31mproxy_off\033[0m"
echo -e "#### 启动命令: \033[32msudo bash start.sh\033[0m"
echo -e "#### 停止命令: \033[31msudo bash shutdown.sh\033[0m"
echo -e "#### 重启命令（不更新订阅）: \033[33msudo bash restart.sh\033[0m"
echo -e "###################################################"
echo -e "\n\n"
echo -e "      -─‐-             -──-‐"
echo -e "     く__,.ヘヽ.        /  ,ー､ 〉"
echo -e "           ＼ ', !-─‐-i  /  /´"
echo -e "          ／｀ｰ'       L/／｀ヽ､"
echo -e "         /   ／,   /|   ,   ,       ',"
echo -e "        ｲ   / /-‐/  ｉ  L_ ﾊ ヽ!   i"
echo -e "        ﾚ ﾍ 7ｲ｀ﾄ   ﾚ'ｧ-ﾄ､!ハ|   |"
echo -e "          !,/7 '0'     ´0iソ|    |"
echo -e "          |.从     _     ,,,, / |./    |"
echo -e "          ﾚ'| i＞.､,,__  _,.イ /   .i   |"
echo -e "           ﾚ'| | / k_７_/ﾚ'ヽ,  ﾊ.  |"
echo -e "             | |/i 〈|/   i  ,.ﾍ |  i  |"
echo -e "            .|/ /  ｉ：    ﾍ!    ＼  |"
echo -e "             kヽ>､ﾊ    _,.ﾍ､    /､!"
echo -e "             !'〈//｀Ｔ´', ＼ ｀'7'ｰr'"
echo -e "             ﾚ'ヽL__|___i,___,ンﾚ|ノ"
echo -e "                  ﾄ-,/  |___./"
echo -e "                  'ｰ'    !_,.:"
echo -e "\n\n"