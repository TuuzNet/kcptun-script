#!/bin/sh

: <<-'EOF'
Fixed
EOF

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 版本信息，请勿修改
# =================
SHELL_VERSION=34
CONFIG_VERSION=7
INIT_VERSION=4
# =================

KCPTUN_INSTALL_DIR='/usr/local/kcptun'
KCPTUN_LOG_DIR='/var/log/kcptun'

# 项目仓库地址，发布到其他账号或组织时只需修改这两个变量
SCRIPT_REPOSITORY="${SCRIPT_REPOSITORY:-TuuzNet/kcptun-script}"
SCRIPT_BRANCH="${SCRIPT_BRANCH:-main}"
KCPTUN_REPOSITORY="${KCPTUN_REPOSITORY:-tobycroft/kcptun}"

# 以下变量均可用环境变量覆盖，便于接入镜像或自建反向代理
KCPTUN_RELEASES_API="${KCPTUN_RELEASES_API:-https://api.github.com/repos/${KCPTUN_REPOSITORY}/releases}"
KCPTUN_LATEST_RELEASE_URL="${KCPTUN_RELEASES_API}/latest"
KCPTUN_TAGS_URL="${KCPTUN_TAGS_URL:-https://github.com/${KCPTUN_REPOSITORY}/tags}"

# GitHub 下载加速前缀，例如 https://ghfast.top/ ；留空表示直连 github.com
GITHUB_PROXY="${GITHUB_PROXY:-}"

# 脚本自身与 version.json 的下载地址
BASE_URL="${KCPTUN_SCRIPT_BASE_URL:-https://github.com/${SCRIPT_REPOSITORY}/raw/${SCRIPT_BRANCH}}"
SHELL_VERSION_INFO_URL="${BASE_URL}/version.json"

# jq 仅在系统未安装时才会下载，版本 1.7.1
JQ_DOWNLOAD_URL='https://github.com/jqlang/jq/releases/download/jq-1.7.1'
JQ_LINUX64_URL="${JQ_DOWNLOAD_URL}/jq-linux-amd64"
JQ_LINUX64_HASH='5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5'
JQ_LINUX32_URL="${JQ_DOWNLOAD_URL}/jq-linux-i386"
JQ_LINUX32_HASH='bc473fd4b385789e9ce3d02a4c8df74dc988a34b20fe4e1a80da997eb360b599'
JQ_LINUX_ARM64_URL="${JQ_DOWNLOAD_URL}/jq-linux-arm64"
JQ_LINUX_ARM64_HASH='4dd2d8a0661df0b22f1bb9a1f9830f06b6f3b8f7d91211a1ef5d7c4f06a8b4a5'
JQ_LINUX_ARMHF_URL="${JQ_DOWNLOAD_URL}/jq-linux-armhf"
JQ_LINUX_ARMHF_HASH='46d18f115cca638efed22b90342d52a84a25ab1bef570551d3a16f7eb065c298'
JQ_LINUX_ARMEL_URL="${JQ_DOWNLOAD_URL}/jq-linux-armel"
JQ_LINUX_ARMEL_HASH='d6b86023e0848c93a618a74b6fd741ce62f5d557fd3c2c1d7870663713b2c174'
JQ_BIN="${KCPTUN_INSTALL_DIR}/bin/jq"
JQ_LOCAL_BIN="$JQ_BIN"

# 服务管理相关路径
SYSTEMD_UNIT_DIR='/etc/systemd/system'
SYSV_INIT_DIR='/etc/init.d'
SERVICE_BACKEND=''

# 旧版由 Supervisor 托管，仅用于升级提示
LEGACY_SUPERVISOR_DIR='/etc/supervisor/conf.d'

# 旧版 Supervisor 迁移版本，设计为较大值，避免与常规版本号冲突
MIGRATE_VERSION=100
MIGRATE_MARKER="${KCPTUN_INSTALL_DIR}/.supervisor-migrated"

# 默认参数
# =======================
D_LISTEN_PORT=29900
D_TARGET_ADDR='127.0.0.1'
D_TARGET_PORT=12984
D_KEY="very fast"
D_CRYPT='aes'
D_MODE='fast'
D_MTU=1350
D_SNDWND=512
D_RCVWND=512
D_DATASHARD=10
D_PARITYSHARD=3
D_DSCP=0
D_NOCOMP='true'
D_QUIET='false'
D_TCP='false'
D_SNMPPERIOD=60
D_PPROF='false'

# 隐藏参数
D_ACKNODELAY='false'
D_NODELAY=1
D_INTERVAL=20
D_RESEND=2
D_NC=1
# SMUX提高到64M提高SreamBuf效果
D_SOCKBUF=67108868
D_SMUXBUF=67108868
D_KEEPALIVE=10

# KCP新版支持，SMux默认为2，BUF大小改为16M
D_SMUXVER=2
D_STREAMBUF=16777217
# ======================

# 当前选择的实例 ID
current_instance_id=""
run_user='kcptun'

clear

cat >&1 <<-'EOF'
#########################################################
# Kcptun 服务端一键安装脚本                             #
# 项目地址: https://github.com/TuuzNet/kcptun-script    #
# 交流群: 94537310                                      #
#########################################################
EOF

# 打印帮助信息
usage() {
	cat >&1 <<-EOF

	请使用: $0 <option>

	可使用的参数 <option> 包括:

	    install          安装
	    uninstall        卸载
	    check            仅检查脚本与 Kcptun 是否有新版本
	    update           检查并执行更新
	    migrate          迁移旧版 Supervisor 部署到 systemd/SysVinit
	    manual           自定义 Kcptun 版本安装
	    help             查看脚本使用说明
	    add              添加一个实例, 多端口加速
	    reconfig <id>    重新配置实例
	    show <id>        显示实例详细配置
	    log <id>         显示实例日志
	    del <id>         删除一个实例

	注: 上述参数中的 <id> 可选, 代表的是实例的ID
	    可使用 1, 2, 3 ... 分别对应实例 kcptun, kcptun2, kcptun3 ...
	    若不指定 <id>, 则默认为 1

	Kcptun 服务管理命令 (systemd):
	    systemctl {start|stop|restart|status} kcptun<id>
	    systemctl {enable|disable} kcptun<id>

	Kcptun 服务管理命令 (SysVinit):
	    service kcptun<id> {start|stop|restart|status}
	EOF

	exit $1
}

# 判断命令是否存在
command_exists() {
	command -v "$@" >/dev/null 2>&1
}

# 判断输入内容是否为数字
is_number() {
	expr "$1" + 1 >/dev/null 2>&1
}

# 按任意键继续
any_key_to_continue() {
	echo "请按任意键继续或 Ctrl + C 退出"
	local saved=""
	saved="$(stty -g)"
	stty -echo
	stty cbreak
	dd if=/dev/tty bs=1 count=1 2>/dev/null
	stty -raw
	stty echo
	stty $saved
}

first_character() {
	if [ -n "$1" ]; then
		echo "$1" | cut -c1
	fi
}

# 检查是否具有 root 权限
check_root() {
	local user=""
	user="$(id -un 2>/dev/null || true)"
	if [ "$user" != "root" ]; then
		cat >&2 <<-'EOF'
		权限错误, 请使用 root 用户运行此脚本!
		EOF
		exit 1
	fi
}

# 获取服务器的IP地址
get_server_ip() {
	local server_ip=""
	local interface_info=""

	if command_exists ip; then
		interface_info="$(ip addr)"
	elif command_exists ifconfig; then
		interface_info="$(ifconfig)"
	fi

	server_ip=$(echo "$interface_info" | \
		grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | \
		grep -vE "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | \
		head -n 1)

	# 自动获取失败时，通过网站提供的 API 获取外网地址
	if [ -z "$server_ip" ]; then
		server_ip="$(https_get 'https://ipv4.icanhazip.com' | tr -d '[:space:]')"
	fi

	echo "$server_ip"
}

# 禁用 selinux
disable_selinux() {
	local selinux_config='/etc/selinux/config'
	if [ -s "$selinux_config" ]; then
		if grep -q "SELINUX=enforcing" "$selinux_config"; then
			sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' "$selinux_config"
			setenforce 0
		fi
	fi
}

# 获取当前操作系统信息
get_os_info() {
	lsb_dist=""
	dist_version=""
	if command_exists lsb_release; then
		lsb_dist="$(lsb_release -si)"
	fi

	if [ -z "$lsb_dist" ]; then
		[ -r /etc/lsb-release ] && lsb_dist="$(. /etc/lsb-release && echo "$DISTRIB_ID")"
		[ -r /etc/debian_version ] && lsb_dist='debian'
		[ -r /etc/fedora-release ] && lsb_dist='fedora'
		[ -r /etc/oracle-release ] && lsb_dist='oracleserver'
		[ -r /etc/centos-release ] && lsb_dist='centos'
		[ -r /etc/redhat-release ] && lsb_dist='redhat'
		[ -r /etc/photon-release ] && lsb_dist='photon'
		[ -r /etc/os-release ] && lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi


	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

	if [ "${lsb_dist}" = "redhatenterpriseserver" ]; then
		lsb_dist='redhat'
	fi

	# 红帽系及衍生发行版统一走 redhat / oraclelinux 分支
	case "$lsb_dist" in
		rhel|rockylinux|rocky|almalinux|alma)
			lsb_dist='redhat'
			;;
		ol|oracle|oraclelinux)
			lsb_dist='oraclelinux'
			;;
	esac

	case "$lsb_dist" in
		ubuntu)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
			;;

		debian|raspbian)
			if [ -r /etc/debian_version ]; then
				dist_version="$(cat /etc/debian_version | sed 's/\/.*//' | sed 's/\..*//')"
			elif [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID" | cut -d'.' -f1)"
			fi
			case "$dist_version" in
				9)
					dist_version="stretch"
					;;
				8)
					dist_version="jessie"
					;;
				7)
					dist_version="wheezy"
					;;
			esac
			;;

		oracleserver)
			lsb_dist="oraclelinux"
			dist_version="$(rpm -q --whatprovides redhat-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//')"
			;;

		fedora|centos|redhat)
			if [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID" | cut -d'.' -f1)"
			fi
			if [ -z "$dist_version" ]; then
				dist_version="$(rpm -q --whatprovides ${lsb_dist}-release --queryformat "%{VERSION}\n" 2>/dev/null | \
					grep -E '^[0-9]' | sed 's/\/.*//' | sed 's/\..*//' | sort | tail -1)"
			fi
			;;

		"vmware photon")
			lsb_dist="photon"
			dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			;;

		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
			;;
	esac

	if [ -z "$lsb_dist" ] || [ -z "$dist_version" ]; then
		cat >&2 <<-EOF
		无法确定服务器系统版本信息。
		请联系脚本作者。
		EOF
		exit 1
	fi
}

# 获取服务器架构，同时确定 Kcptun 与 jq 的下载文件
# 结果写入 file_suffix / jq_url / jq_hash
get_arch() {
	architecture="$(uname -m)"
	case "$architecture" in
		amd64|x86_64)
			file_suffix='linux_amd64'
			jq_url="$JQ_LINUX64_URL"
			jq_hash="$JQ_LINUX64_HASH"
			;;
		i386|i486|i586|i686|x86)
			file_suffix='linux_386'
			jq_url="$JQ_LINUX32_URL"
			jq_hash="$JQ_LINUX32_HASH"
			;;
		aarch64|arm64)
			file_suffix='linux_arm64'
			jq_url="$JQ_LINUX_ARM64_URL"
			jq_hash="$JQ_LINUX_ARM64_HASH"
			;;
		armv7l|armv7|armv6l|armv6|arm)
			file_suffix='linux_arm'
			jq_url="$JQ_LINUX_ARMHF_URL"
			jq_hash="$JQ_LINUX_ARMHF_HASH"
			;;
		armv5tel|armv5l|armv5)
			file_suffix='linux_arm'
			jq_url="$JQ_LINUX_ARMEL_URL"
			jq_hash="$JQ_LINUX_ARMEL_HASH"
			;;
		*)
			cat 1>&2 <<-EOF
			当前脚本支持 amd64 / x86 / arm64 / arm 架构
			你的系统为: $architecture
			EOF
			exit 1
			;;
	esac
}

# 为 github.com 下载地址拼接加速前缀
url_with_proxy() {
	case "$1" in
		https://github.com/*)
			if [ -n "$GITHUB_PROXY" ]; then
				printf '%s%s' "$(printf '%s' "$GITHUB_PROXY" | sed 's:/*$::')/" "$1"
				return 0
			fi
			;;
	esac

	printf '%s' "$1"
}

# 输出 URL 内容，优先 wget，缺失时回退 curl
https_get() {
	local url=""
	url="$(url_with_proxy "$1")"

	if command_exists wget; then
		wget -qO- --no-check-certificate "$url"
	elif command_exists curl; then
		curl -fsSL --insecure "$url"
	else
		return 1
	fi
}

# 下载文件，优先 wget，缺失时回退 curl
https_download() {
	local url=""
	url="$(url_with_proxy "$1")"
	local file="$2"

	if command_exists wget; then
		wget -O "$file" --no-check-certificate "$url"
	elif command_exists curl; then
		curl -fsSL --insecure -o "$file" "$url"
	else
		return 1
	fi
}

# 快速获取 URL 内容，用于启动时的版本提示，超时或失败不阻塞
https_get_quick() {
	local url=""
	url="$(url_with_proxy "$1")"

	if command_exists wget; then
		wget -qO- --no-check-certificate --tries=1 --timeout=5 "$url"
	elif command_exists curl; then
		curl -fsSL --insecure --max-time 5 "$url"
	else
		return 1
	fi
}

# 获取 API 内容
get_content() {
	local url="$1"
	local fatal="${2:-true}"
	local retry=0

	local content=""
	get_network_content() {
		if [ $retry -ge 3 ]; then
			if [ "$fatal" = "true" ]; then
				cat >&2 <<-EOF
				获取网络信息失败!
				URL: ${url}
				安装脚本需要能访问 GitHub，请检查服务器网络。
				国内服务器可设置 GITHUB_PROXY 或 KCPTUN_RELEASES_API 使用镜像。
				EOF
				exit 1
			fi
			return 1
		fi

		# 将所有的换行符替换为自定义标签，防止 jq 解析失败
		content="$(https_get "$url" | sed -r 's/(\\r)?\\n/#br#/g')"

		if [ "$?" != "0" ] || [ -z "$content" ]; then
			retry=$(expr $retry + 1)
			get_network_content
		fi
	}

	get_network_content || return 1
	echo "$content"
}

# 下载文件， 默认重试 3 次
download_file() {
	local url="$1"
	local file="$2"
	local verify="$3"
	local retry=0
	local verify_cmd=""

	verify_file() {
		if [ -z "$verify_cmd" ] && [ -n "$verify" ]; then
			if [ "${#verify}" = "32" ]; then
				verify_cmd="md5sum"
			elif [ "${#verify}" = "40" ]; then
				verify_cmd="sha1sum"
			elif [ "${#verify}" = "64" ]; then
				verify_cmd="sha256sum"
			elif [ "${#verify}" = "128" ]; then
				verify_cmd="sha512sum"
			fi

			if [ -n "$verify_cmd" ] && ! command_exists "$verify_cmd"; then
				if [ "$verify_cmd" = "sha256sum" ] && command_exists shasum; then
					# macOS 等系统只有 shasum
					verify_cmd="shasum -a 256"
				else
					verify_cmd=""
				fi
			fi
		fi

		if [ -s "$file" ] && [ -n "$verify_cmd" ]; then
			(
				set -x
				echo "${verify}  ${file}" | $verify_cmd -c
			)
			return $?
		fi

		return 1
	}

	download_file_to_path() {
		if verify_file; then
			return 0
		fi

		if [ $retry -ge 3 ]; then
			rm -f "$file"
			cat >&2 <<-EOF
			文件下载或校验失败! 请重试。
			URL: ${url}
			EOF

			if [ -n "$verify_cmd" ]; then
				cat >&2 <<-EOF
				如果下载多次失败，你可以手动下载文件:
				1. 下载文件 ${url}
				2. 将文件重命名为 $(basename "$file")
				3. 上传文件至目录 $(dirname "$file")
				4. 重新运行安装脚本

				注: 文件目录 . 表示当前目录，.. 表示当前目录的上级目录
				EOF
			fi
			exit 1
		fi

		( set -x; https_download "$url" "$file" )
		if [ "$?" != "0" ] || [ -n "$verify_cmd" ] && ! verify_file; then
			retry=$(expr $retry + 1)
			download_file_to_path
		fi
	}

	download_file_to_path
}

# 安装 jq 用于解析和生成 json 文件
# 优先使用发行版仓库中的 jq，无法安装时再下载官方静态二进制
install_jq() {
	check_jq() {
		if command_exists jq && ( jq --version >/dev/null 2>&1 ); then
			JQ_BIN="$(command -v jq)"
			is_checked_jq="true"
			return 0
		fi

		JQ_BIN="$JQ_LOCAL_BIN"

		if [ ! -f "$JQ_BIN" ]; then
			return 1
		fi

		[ ! -x "$JQ_BIN" ] && chmod a+x "$JQ_BIN"

		if ( $JQ_BIN --help 2>/dev/null | grep -q "JSON" ); then
			is_checked_jq="true"
			return 0
		else
			rm -f "$JQ_BIN"
			return 1
		fi
	}

	install_jq_from_package() {
		if [ -z "$lsb_dist" ]; then
			get_os_info
		fi

		case "$lsb_dist" in
			ubuntu|debian|raspbian)
				( set -x; apt-get update ) >/dev/null 2>&1
				( set -x; apt-get install -y -q jq ) >/dev/null 2>&1 || true
				;;
			fedora|centos|redhat|oraclelinux|photon)
				local jq_mgr=""
				if command_exists dnf; then
					jq_mgr="dnf -y -q"
				elif command_exists tdnf; then
					jq_mgr="tdnf -y"
				elif command_exists yum; then
					jq_mgr="yum -y -q"
				fi

				if [ -z "$jq_mgr" ]; then
					return 0
				fi

				if ! ( set -x; $jq_mgr install jq ) >/dev/null 2>&1; then
					if [ "$jq_mgr" = "yum -y -q" ]; then
						# CentOS 7 等系统的 jq 位于 EPEL，先启用扩展源后重试
						( set -x; yum -y -q install epel-release ) >/dev/null 2>&1 || true
						( set -x; yum -y -q install jq ) >/dev/null 2>&1 || true
					fi
				fi
				;;
		esac
	}

	if [ -z "$is_checked_jq" ] && ! check_jq; then
		install_jq_from_package

		if ! check_jq; then
			if [ -z "$file_suffix" ]; then
				get_arch
			fi

			local dir=""
			dir="$(dirname "$JQ_BIN")"
			if [ ! -d "$dir" ]; then
				(
					set -x
					mkdir -p "$dir"
				)
			fi

			download_file "$jq_url" "$JQ_BIN" "$jq_hash"

			if ! check_jq; then
				cat >&2 <<-EOF
				未找到适用于当前系统的 JSON 解析软件 jq
				EOF
				exit 1
			fi
		fi

		return 0
	fi
}

# 读取 json 文件中某一项的值
get_json_string() {
	install_jq

	local content="$1"
	local selector="$2"
	local regex="$3"

	local str=""
	if [ -n "$content" ]; then
		str="$(echo "$content" | $JQ_BIN -r "$selector" 2>/dev/null)"

		if [ -n "$str" ] && [ -n "$regex" ]; then
			str="$(echo "$str" | grep -oE "$regex")"
		fi
	fi
	echo "$str"
}

# 获取当前实例的文件路径，传入参数：
# * config: kcptun 服务端配置文件
# * log: kcptun 日志文件路径
# * snmp: kcptun snmp 日志文件路径
# * service: 实例的服务文件路径（systemd unit 或 init 脚本）
get_current_file() {
	case "$1" in
		config)
			printf '%s/server-config%s.json' "$KCPTUN_INSTALL_DIR" "$current_instance_id"
			;;
		log)
			printf '%s/server%s.log' "$KCPTUN_LOG_DIR" "$current_instance_id"
			;;
		snmp)
			printf '%s/snmplog%s.log' "$KCPTUN_LOG_DIR" "$current_instance_id"
			;;
		service)
			get_service_file_path "$current_instance_id"
			;;
	esac
}

# 检测服务管理方式，结果写入 SERVICE_BACKEND
detect_service_backend() {
	if [ -n "$SERVICE_BACKEND" ]; then
		return 0
	fi

	if command_exists systemctl && [ -d '/run/systemd/system' ]; then
		SERVICE_BACKEND='systemd'
	elif command_exists service; then
		SERVICE_BACKEND='sysvinit'
	else
		cat >&2 <<-'EOF'
		当前服务器未检测到 systemd 或 service 命令，无法配置服务。
		请先手动安装 systemd 或 SysVinit 之后再运行脚本。
		EOF
		exit 1
	fi
}

# 获取实例的服务文件路径，实例 ID 为空表示第一个实例
get_service_file_path() {
	detect_service_backend

	if [ "$SERVICE_BACKEND" = 'systemd' ]; then
		printf '%s/kcptun%s.service' "$SYSTEMD_UNIT_DIR" "$1"
	else
		printf '%s/kcptun%s' "$SYSV_INIT_DIR" "$1"
	fi
}

# 列出所有实例的服务文件名（按最后修改时间排序）
list_instance_files() {
	detect_service_backend

	if [ "$SERVICE_BACKEND" = 'systemd' ]; then
		ls -lt "$SYSTEMD_UNIT_DIR" 2>/dev/null | grep "^-" | awk '{print $9}' | grep -E "^kcptun[0-9]*\.service$"
	else
		ls -lt "$SYSV_INIT_DIR" 2>/dev/null | grep "^-" | awk '{print $9}' | grep -E "^kcptun[0-9]*$"
	fi
}

# 获取实例数量
get_instance_count() {
	list_instance_files | wc -l | tr -d ' '
}

# 重新加载服务管理器配置
reload_service_manager() {
	detect_service_backend

	if [ "$SERVICE_BACKEND" = 'systemd' ]; then
		systemctl daemon-reload >/dev/null 2>&1
	fi
}

# 启动实例
start_instance_service() {
	local instance_id="$1"
	detect_service_backend

	if [ "$SERVICE_BACKEND" = 'systemd' ]; then
		systemctl start "kcptun${instance_id}.service"
	else
		service "kcptun${instance_id}" start
	fi
}

# 停止实例
stop_instance_service() {
	local instance_id="$1"
	detect_service_backend

	if [ "$SERVICE_BACKEND" = 'systemd' ]; then
		systemctl stop "kcptun${instance_id}.service" >/dev/null 2>&1
	else
		service "kcptun${instance_id}" stop >/dev/null 2>&1
	fi
}

# 重启实例
restart_instance_service() {
	local instance_id="$1"
	detect_service_backend

	if [ "$SERVICE_BACKEND" = 'systemd' ]; then
		systemctl restart "kcptun${instance_id}.service"
	else
		service "kcptun${instance_id}" restart
	fi
}

# 设置实例开机自启
enable_instance_service() {
	local instance_id="$1"
	detect_service_backend

	if [ "$SERVICE_BACKEND" = 'systemd' ]; then
		systemctl enable "kcptun${instance_id}.service" >/dev/null 2>&1
	elif command_exists chkconfig; then
		chkconfig --add "kcptun${instance_id}" >/dev/null 2>&1
		chkconfig "kcptun${instance_id}" on >/dev/null 2>&1
	elif command_exists update-rc.d; then
		update-rc.d "kcptun${instance_id}" defaults >/dev/null 2>&1
	fi
}

# 取消实例开机自启
disable_instance_service() {
	local instance_id="$1"
	detect_service_backend

	if [ "$SERVICE_BACKEND" = 'systemd' ]; then
		systemctl disable "kcptun${instance_id}.service" >/dev/null 2>&1
	elif command_exists chkconfig; then
		chkconfig "kcptun${instance_id}" off >/dev/null 2>&1
		chkconfig --del "kcptun${instance_id}" >/dev/null 2>&1
	elif command_exists update-rc.d; then
		update-rc.d -f "kcptun${instance_id}" remove >/dev/null 2>&1
	fi
}

# 通过 API 获取对应版本号 Kcptun 的 release 信息
# 传入 Kcptun 版本号
get_kcptun_version_info() {
	local request_version="$1"
	local fatal="${2:-true}"

	local version_content=""
	if [ -n "$request_version" ]; then
		local json_content=""
		json_content="$(get_content "${KCPTUN_RELEASES_API}?per_page=100" "$fatal")"
		local version_selector=".[] | select(.tag_name == \"${request_version}\")"
		version_content="$(get_json_string "$json_content" "$version_selector")"
	else
		version_content="$(get_content "$KCPTUN_LATEST_RELEASE_URL" "$fatal")"
	fi

	if [ -z "$version_content" ]; then
		return 1
	fi

	if [ -z "$file_suffix" ]; then
		get_arch
	fi

	local server_asset="server_${file_suffix}"
	local url_selector=".assets[] | select(.name == \"${server_asset}\") | .browser_download_url"
	kcptun_release_download_url="$(get_json_string "$version_content" "$url_selector")"

	if [ -z "$kcptun_release_download_url" ]; then
		return 1
	fi

	local checksums_selector=".assets[] | select(.name == \"checksums.txt\") | .browser_download_url"
	kcptun_release_checksums_url="$(get_json_string "$version_content" "$checksums_selector")"

	kcptun_release_tag_name="$(get_json_string "$version_content" '.tag_name')"
	kcptun_release_name="$(get_json_string "$version_content" '.name')"
	kcptun_release_prerelease="$(get_json_string "$version_content" '.prerelease')"
	kcptun_release_publish_time="$(get_json_string "$version_content" '.published_at')"
	kcptun_release_html_url="$(get_json_string "$version_content" '.html_url')"

	local body_content="$(get_json_string "$version_content" '.body')"
	local body="$(echo "$body_content" | sed 's/#br#/\n/g' | grep -vE '(^```)|(^>)|(^[[:space:]]*$)')"

	# 更新说明中去掉长串哈希，避免刷屏
	kcptun_release_body="$(echo "$body" | grep -vE "[0-9a-zA-Z]{32,}")"

	return 0
}

# 从 Release 的 checksums.txt 中查询目标文件的 SHA256
get_kcptun_checksum() {
	local asset_name="$1"
	local checksum_content=""

	if [ -z "$kcptun_release_checksums_url" ]; then
		return 0
	fi

	checksum_content="$(https_get "$kcptun_release_checksums_url")"
	if [ -z "$checksum_content" ]; then
		return 0
	fi

	echo "$checksum_content" | \
		awk -v plain="$asset_name" -v prefixed="./$asset_name" \
			'$2 == plain || $2 == prefixed { print $1; exit }'
}

# 获取脚本版本信息
get_shell_version_info() {
	local fatal="${1:-true}"
	local shell_version_content=""
	shell_version_content="$(get_content "$SHELL_VERSION_INFO_URL" "$fatal")"
	if [ -z "$shell_version_content" ]; then
		return 1
	fi

	new_shell_version="$(get_json_string "$shell_version_content" '.shell_version' '[0-9]+')"
	new_config_version="$(get_json_string "$shell_version_content" '.config_version' '[0-9]+')"
	new_init_version="$(get_json_string "$shell_version_content" '.init_version' '[0-9]+')"

	shell_change_log="$(get_json_string "$shell_version_content" '.change_log')"
	config_change_log="$(get_json_string "$shell_version_content" '.config_change_log')"
	init_change_log="$(get_json_string "$shell_version_content" '.init_change_log')"
	new_shell_url="$(get_json_string "$shell_version_content" '.shell_url')"
	shell_release_url="$(get_json_string "$shell_version_content" '.release_url')"
	new_shell_sha256="$(get_json_string "$shell_version_content" '.shell_sha256')"


	if [ -z "$new_shell_version" ]; then
		new_shell_version="0"
	fi
	if [ -z "$new_config_version" ]; then
		new_config_version="0"
	fi
	if [ -z "$new_init_version" ]; then
		new_init_version="0"
	fi

	return 0
}

# 下载并安装 Kcptun 服务端
install_kcptun() {
	if [ -z "$kcptun_release_download_url" ]; then
		get_kcptun_version_info "$1"

		if [ "$?" != "0" ]; then
			cat >&2 <<-'EOF'
			获取 Kcptun 版本信息或下载地址失败!
			可能是 GitHub 改版，或者从网络获取到的内容不正确。
			请联系脚本作者。
			EOF
			exit 1
		fi
	fi

	if [ -z "$file_suffix" ]; then
		get_arch
	fi

	if [ ! -d "$KCPTUN_INSTALL_DIR" ]; then
		(
			set -x
			mkdir -p "$KCPTUN_INSTALL_DIR"
		)
	fi

	if [ ! -d "$KCPTUN_LOG_DIR" ]; then
		(
			set -x
			mkdir -p "$KCPTUN_LOG_DIR"
		)
	fi

	# 允许非 root 运行用户写入日志
	chmod a+w "$KCPTUN_LOG_DIR" 2>/dev/null || true

	local server_asset="server_${file_suffix}"
	local kcptun_server_file="${KCPTUN_INSTALL_DIR}/${server_asset}"

	local file_verify=""
	file_verify="$(get_kcptun_checksum "$server_asset")"
	if [ -z "$file_verify" ]; then
		cat >&1 <<-EOF
		警告: 未能获取 ${server_asset} 的校验值，将跳过完整性校验。
		EOF
	fi

	# 先下载到临时文件再替换，避免覆盖运行中的二进制时报 Text file busy
	local download_temp="${kcptun_server_file}.download"
	download_file "$kcptun_release_download_url" "$download_temp" "$file_verify"

	if [ ! -s "$download_temp" ]; then
		cat >&2 <<-EOF
		未找到下载的 Kcptun 服务端执行文件: ${kcptun_server_file}
		你可以尝试重新安装，或者联系脚本作者。
		EOF
		exit 1
	fi

	(
		set -x
		mv -f "$download_temp" "$kcptun_server_file"
		chmod a+x "$kcptun_server_file"
	)

	if [ -z "$(get_installed_version)" ]; then
		cat >&2 <<-'EOF'
		无法运行当前服务器上的 kcptun 可执行文件
		可能是不支持的架构，你可以尝试从源码编译。
		EOF
		exit 1
	fi

	# 清理旧版本残留的客户端文件与压缩包
	rm -f "${KCPTUN_INSTALL_DIR}/client_${file_suffix}" \
		"${KCPTUN_INSTALL_DIR}/kcptun-"*.tar.gz 2>/dev/null || true
}

# 安装基础依赖软件
# 已不再依赖 python / pip / supervisor，仅保留下载与文本处理工具
install_deps() {
	if [ -z "$lsb_dist" ]; then
		get_os_info
	fi

	did_apt_get_update=""
	deps_failed=""

	apt_get_update() {
		if [ -z "$did_apt_get_update" ]; then
			( set -x; sleep 3; apt-get update ) || deps_failed="true"
			did_apt_get_update=1
		fi
	}

	case "$lsb_dist" in
		ubuntu|debian|raspbian)
			if ! command_exists wget && ! command_exists curl; then
				apt_get_update
				( set -x; sleep 3; apt-get install -y -q wget ca-certificates ) || deps_failed="true"
			fi

			if ! command_exists awk; then
				apt_get_update
				( set -x; sleep 3; apt-get install -y -q gawk ) || deps_failed="true"
			fi
			;;
		fedora|centos|redhat|oraclelinux|photon)
			local pkg_mgr=""
			if command_exists dnf; then
				pkg_mgr="dnf -y -q"
			elif command_exists tdnf; then
				pkg_mgr="tdnf -y"
			elif command_exists yum; then
				pkg_mgr="yum -y -q"
			fi

			if [ -z "$pkg_mgr" ]; then
				deps_failed="true"
			else
				if ! command_exists wget && ! command_exists curl; then
					( set -x; sleep 3; $pkg_mgr install wget ca-certificates ) || deps_failed="true"
				fi

				if ! command_exists awk; then
					( set -x; sleep 3; $pkg_mgr install gawk ) || deps_failed="true"
				fi
			fi
			;;
		*)
			cat >&2 <<-EOF
			暂时不支持当前系统：${lsb_dist} ${dist_version}
			EOF

			exit 1
			;;
	esac

	if [ -n "$deps_failed" ]; then
		cat >&2 <<-'EOF'
		一些依赖软件安装失败，
		请查看日志检查错误。
		EOF
		exit 1
	fi

	install_jq
}

# 配置服务管理器（systemd 或 SysVinit）
install_service_manager() {
	detect_service_backend

	if [ "$SERVICE_BACKEND" = 'systemd' ]; then
		cat >&1 <<-'EOF'
		检测到 systemd，将使用 systemd 托管 Kcptun 服务。
		EOF
	else
		cat >&1 <<-'EOF'
		检测到 SysVinit，将为每个实例生成独立的 init 脚本。
		EOF
	fi

	migrate_legacy_supervisor
}

# 是否存在由 Supervisor 托管的其他程序（避免误卸载）
has_other_supervisor_programs() {
	local conf=""
	for conf in "$LEGACY_SUPERVISOR_DIR"/*.conf; do
		[ -f "$conf" ] || continue
		case "$(basename "$conf")" in
			kcptun*.conf) ;;
			*) return 0 ;;
		esac
	done

	return 1
}

# 列出由 Supervisor 托管的其他程序
list_other_supervisor_programs() {
	local conf=""
	for conf in "$LEGACY_SUPERVISOR_DIR"/*.conf; do
		[ -f "$conf" ] || continue
		case "$(basename "$conf")" in
			kcptun*.conf) ;;
			*) basename "$conf" ;;
		esac
	done
}

# 迁移完成后卸载旧版 Supervisor
# 只清理本脚本安装的内容，不删除发行版包管理器维护的二进制
uninstall_supervisor() {
	if has_other_supervisor_programs; then
		cat >&1 <<-EOF
		Supervisor 仍在管理其他程序，已跳过卸载:
		$(list_other_supervisor_programs | sed 's/^/  /')
		如需卸载，请先迁移这些程序。
		EOF
		return 0
	fi

	cat >&1 <<-'EOF'
	旧版 Supervisor 已不再需要，是否卸载?
	注意: 会停止并删除 supervisord 服务、/etc/supervisor 目录与命令软链。
	EOF

	local yn=""
	read -p "(默认: 卸载) [y/n]: " yn
	case "$(first_character "$yn")" in
		n|N)
			return 0
			;;
	esac

	if command_exists systemctl; then
		systemctl stop supervisord.service >/dev/null 2>&1 || true
		systemctl disable supervisord.service >/dev/null 2>&1 || true
	fi

	if command_exists service; then
		service supervisord stop >/dev/null 2>&1 || true
	fi

	if command_exists chkconfig; then
		chkconfig supervisord off >/dev/null 2>&1 || true
		chkconfig --del supervisord >/dev/null 2>&1 || true
	fi

	if command_exists update-rc.d; then
		update-rc.d -f supervisord remove >/dev/null 2>&1 || true
	fi

	if command_exists pip; then
		(
			set -x
			pip uninstall -y supervisor
		) >/dev/null 2>&1 || true
	fi

	(
		set -x
		rm -f "$SYSTEMD_UNIT_DIR/supervisord.service" \
			'/lib/systemd/system/supervisord.service' \
			'/etc/init.d/supervisord'
		rm -rf '/etc/supervisor'
		rm -f '/usr/local/bin/supervisord' \
			'/usr/local/bin/supervisorctl' \
			'/usr/local/bin/pidproxy' \
			'/usr/local/bin/echo_supervisord_conf'
	)
	reload_service_manager

	if command_exists dpkg && dpkg -S '/usr/bin/supervisord' >/dev/null 2>&1; then
		cat >&1 <<-EOF
		提示: /usr/bin/supervisord 由系统包管理器安装，
		如需彻底清理请执行: apt-get remove -y supervisor
		EOF
	elif command_exists rpm && rpm -q supervisor >/dev/null 2>&1; then
		cat >&1 <<-EOF
		提示: supervisor 为系统包，如需彻底清理请执行: yum remove -y supervisor
		EOF
	fi

	cat >&1 <<-EOF
	Supervisor 已卸载。
	EOF
}

# 是否存在旧版 Supervisor 托管的实例
has_legacy_instances() {
	[ -d "$LEGACY_SUPERVISOR_DIR" ] && \
		ls "$LEGACY_SUPERVISOR_DIR"/kcptun*.conf >/dev/null 2>&1
}

# 获取旧版 Supervisor 实例数量
get_legacy_instance_count() {
	if has_legacy_instances; then
		ls "$LEGACY_SUPERVISOR_DIR"/kcptun*.conf | wc -l | tr -d ' '
	else
		echo "0"
	fi
}

# 将旧版 Supervisor 托管的实例自动迁移到当前服务管理方式
# 沿用实例已有的 server-config<id>.json，不需要用户重新输入配置
migrate_legacy_instances() {
	if ! has_legacy_instances; then
		return 0
	fi

	detect_service_backend

	local legacy_count=""
	legacy_count="$(get_legacy_instance_count)"

	cat >&1 <<-EOF
	检测到 ${legacy_count} 个由旧版 Supervisor 托管的 Kcptun 实例，正在自动迁移到 ${SERVICE_BACKEND}。
	迁移过程中服务会短暂中断，实例配置保持不变，无需重新配置。
	EOF

	local backup_instance_id="$current_instance_id"
	local backup_run_user="$run_user"
	local conf=""
	local instance_id=""
	local config_file=""
	local log_file=""
	local migrated="0"
	local failed="0"

	if [ ! -d "$KCPTUN_LOG_DIR" ]; then
		(
			set -x
			mkdir -p "$KCPTUN_LOG_DIR"
		)
	fi
	chmod a+w "$KCPTUN_LOG_DIR" 2>/dev/null || true

	for conf in "$LEGACY_SUPERVISOR_DIR"/kcptun*.conf; do
		[ -f "$conf" ] || continue

		instance_id="$(basename "$conf" .conf | sed 's/^kcptun//')"
		current_instance_id="$instance_id"
		config_file="$(get_current_file 'config')"

		if [ ! -s "$config_file" ]; then
			cat >&1 <<-EOF
			跳过实例 kcptun${instance_id}: 未找到配置文件 ${config_file}
			EOF
			failed=$(expr $failed + 1)
			continue
		fi

		# 按配置推断运行用户，并确保日志可写
		run_user="$(get_instance_run_user "$instance_id")"
		log_file="$(get_current_file 'log')"
		if [ -f "$log_file" ] && [ "$run_user" != "root" ]; then
			chown "$run_user" "$log_file" 2>/dev/null || true
		fi

		# 备份旧配置，便于迁移失败时回滚
		mkdir -p "${KCPTUN_INSTALL_DIR}/.legacy-supervisor" 2>/dev/null || true
		cp -f "$conf" "${KCPTUN_INSTALL_DIR}/.legacy-supervisor/" 2>/dev/null || true

		# 生成当前服务管理方式对应的服务文件
		gen_service_file

		# 先停止旧实例，但保留旧配置，启动成功后再删除
		if command_exists supervisorctl; then
			supervisorctl stop "kcptun${instance_id}" >/dev/null 2>&1 || true
		fi

		reload_service_manager
		enable_instance_service "$instance_id"

		if start_instance_service "$instance_id" >/dev/null 2>&1; then
			migrated=$(expr $migrated + 1)
			rm -f "$conf"
			cat >&1 <<-EOF
			实例 kcptun${instance_id} 已迁移: $(get_current_file 'service')
			EOF
		else
			failed=$(expr $failed + 1)
			cat >&2 <<-EOF
			实例 kcptun${instance_id} 启动失败，已保留旧配置: ${conf}
			可执行 'supervisorctl start kcptun${instance_id}' 回滚，或使用 '$0 log ${instance_id:-1}' 查看日志。
			EOF
		fi
	done

	if command_exists supervisorctl; then
		supervisorctl update >/dev/null 2>&1 || true
	fi

	current_instance_id="$backup_instance_id"
	run_user="$backup_run_user"

	cat >&1 <<-EOF
	迁移完成: 成功 ${migrated} 个，失败 ${failed} 个。
	EOF

	if [ "$failed" -eq 0 ]; then
		echo "$MIGRATE_VERSION" > "$MIGRATE_MARKER" 2>/dev/null || true
		uninstall_supervisor
	else
		cat >&1 <<-'EOF'
		有实例迁移失败，已保留 Supervisor 配置，暂不卸载 Supervisor。
		EOF
	fi

	any_key_to_continue
}

# 检测并迁移旧版 Supervisor 托管的实例（交互式兜底）
migrate_legacy_supervisor() {
	if [ ! -d "$LEGACY_SUPERVISOR_DIR" ] || \
		! ls "$LEGACY_SUPERVISOR_DIR"/kcptun*.conf >/dev/null 2>&1; then
		return 0
	fi

	cat >&1 <<-EOF
	检测到旧版由 Supervisor 托管的 Kcptun 实例:
	  ${LEGACY_SUPERVISOR_DIR}/kcptun*.conf
	新版本改用 ${SERVICE_BACKEND} 托管，继续安装前需要处理旧实例，
	否则同一端口可能会启动两个进程。
	EOF

	local sel=""
	read -p "(默认: 停止并移除旧配置) 请选择 [1]移除 [2]保留: " sel
	case "$(first_character "$sel")" in
		2)
			return 0
			;;
	esac

	local conf=""
	local name=""
	for conf in "$LEGACY_SUPERVISOR_DIR"/kcptun*.conf; do
		name="$(basename "$conf" .conf)"
		if command_exists supervisorctl; then
			supervisorctl stop "$name" >/dev/null 2>&1 || true
		fi
		(
			set -x
			rm -f "$conf"
		)
	done

	if command_exists supervisorctl; then
		supervisorctl update >/dev/null 2>&1 || true
	fi
}

# 生成当前实例的服务文件
gen_service_file() {
	if [ -z "$SERVICE_BACKEND" ]; then
		detect_service_backend
	fi

	if [ "$SERVICE_BACKEND" = 'systemd' ]; then
		gen_systemd_unit
	else
		gen_sysv_init
	fi
}

# 生成 systemd unit 文件
gen_systemd_unit() {
	local unit_file=""
	unit_file="$(get_service_file_path "$current_instance_id")"
	local server_file=""
	server_file="$(get_kcptun_server_file)"
	local config_file=""
	config_file="$(get_current_file 'config')"
	local log_file=""
	log_file="$(get_current_file 'log')"

	cat > "$unit_file" <<-EOF
	[Unit]
	Description=Kcptun Server (kcptun${current_instance_id})
	After=network-online.target
	Wants=network-online.target

	[Service]
	Type=simple
	User=${run_user}
	WorkingDirectory=${KCPTUN_INSTALL_DIR}
	ExecStart=/bin/sh -c 'exec ${server_file} -c ${config_file} >> ${log_file} 2>&1'
	Restart=always
	RestartSec=3
	LimitNOFILE=1048576

	[Install]
	WantedBy=multi-user.target
	EOF
}

# 生成 SysVinit init 脚本
gen_sysv_init() {
	local init_file=""
	init_file="$(get_service_file_path "$current_instance_id")"
	local server_file=""
	server_file="$(get_kcptun_server_file)"
	local config_file=""
	config_file="$(get_current_file 'config')"
	local log_file=""
	log_file="$(get_current_file 'log')"
	local pid_file="/var/run/kcptun${current_instance_id}.pid"

	cat > "$init_file" <<-EOF
	#!/bin/sh
	### BEGIN INIT INFO
	# Provides:          kcptun${current_instance_id}
	# Required-Start:    \$network \$remote_fs
	# Required-Stop:     \$network \$remote_fs
	# Default-Start:     2 3 4 5
	# Default-Stop:      0 1 6
	# Short-Description: Kcptun Server (kcptun${current_instance_id})
	### END INIT INFO

	DAEMON="${server_file}"
	CONFIG="${config_file}"
	LOGFILE="${log_file}"
	PIDFILE="${pid_file}"
	RUN_USER="${run_user}"

	is_running() {
		[ -f "\$PIDFILE" ] && kill -0 "\$(cat "\$PIDFILE")" 2>/dev/null
	}

	start_daemon() {
		nohup "\$DAEMON" -c "\$CONFIG" >> "\$LOGFILE" 2>&1 &
		echo \$! > "\$PIDFILE"
	}

	start() {
		if is_running; then
			echo "kcptun${current_instance_id} is already running"
			return 0
		fi

		: > "\$PIDFILE"
		chown "\$RUN_USER" "\$PIDFILE" 2>/dev/null

		if [ "\$RUN_USER" = "root" ]; then
			start_daemon
		else
			su -s /bin/sh -c "\$0 __start_daemon" "\$RUN_USER"
		fi
	}

	stop() {
		if [ -f "\$PIDFILE" ]; then
			kill "\$(cat "\$PIDFILE")" 2>/dev/null
			rm -f "\$PIDFILE"
		fi
	}

	status() {
		if is_running; then
			echo "kcptun${current_instance_id} is running"
			return 0
		fi
		echo "kcptun${current_instance_id} is stopped"
		return 3
	}

	case "\$1" in
		start) start ;;
		stop) stop ;;
		restart) stop; sleep 1; start ;;
		status) status ;;
		__start_daemon) start_daemon ;;
		*) echo "Usage: \$0 {start|stop|restart|status}"; exit 1 ;;
	esac
	EOF

	(
		set -x
		chmod a+x "$init_file"
	)
}


# 应用服务配置变更：重载配置并重启当前实例
apply_service_config() {
	detect_service_backend
	reload_service_manager

	local service_file=""
	service_file="$(get_current_file 'service')"
	if [ ! -f "$service_file" ]; then
		return 0
	fi

	( set -x; sleep 3 )
	if ! restart_instance_service "$current_instance_id"; then
		cat >&2 <<-'EOF'
		启动 Kcptun 服务失败，请查看日志获取原因。
		EOF
		exit 1
	fi
}

# 重新生成全部实例的服务文件（服务管理方式升级时使用）
regenerate_service_files() {
	detect_service_backend

	local backup_instance_id="$current_instance_id"
	local backup_run_user="$run_user"
	local file=""
	local instance_id=""

	for file in $(list_instance_files); do
		instance_id="$(echo "$file" | sed -e 's/^kcptun//' -e 's/\.service$//')"
		current_instance_id="$instance_id"
		run_user="$(get_instance_run_user "$instance_id")"
		gen_service_file
	done

	current_instance_id="$backup_instance_id"
	run_user="$backup_run_user"
	reload_service_manager
}

# 从实例配置文件推断运行用户
get_instance_run_user() {
	local instance_id="$1"
	local config_file="${KCPTUN_INSTALL_DIR}/server-config${instance_id}.json"
	local tcp="false"
	local listen=""
	local port=""
	local start_port=""

	if [ -f "$config_file" ]; then
		local content=""
		content="$(cat "$config_file")"
		tcp="$(get_json_string "$content" '.tcp')"
		listen="$(get_json_string "$content" '.listen')"
	fi

	port="${listen##*:}"
	start_port="${port%%-*}"

	if [ "$tcp" = "true" ] || ( is_number "$start_port" && [ "$start_port" -le 1024 ] ); then
		echo 'root'
	else
		echo 'kcptun'
	fi
}

set_kcptun_config() {
	is_port() {
		local port="$1"
		is_number "$port" && \
			[ $port -ge 1 ] && [ $port -le 65535 ]
	}

	port_using() {
		local port="$1"

		if command_exists netstat; then
			( netstat -ntul | grep -qE "[0-9:*]:${port}\s" )
		elif command_exists ss; then
			( ss -ntul | grep -qE "[0-9:*]:${port}\s" )
		else
			return 0
		fi

		return $?
	}

	local input=""
	local yn=""

	# 设置服务运行端口
	[ -z "$listen_port" ] && listen_port="$D_LISTEN_PORT"
	while true
	do
		cat >&1 <<-'EOF'
		请输入 Kcptun 服务端运行端口 [1~65535]
		这个端口就是 Kcptun 客户端连接的端口
		新版支持端口范围，可输入[30000-35000]来开启端口范围
		EOF
		read -p "(默认: ${listen_port}): " input

		if [ -n "$input" ]; then
			if echo "$input" | grep -qE '^[0-9]+-[0-9]+$'; then
				range_start=$(echo "$input" | cut -d'-' -f1)
				range_end=$(echo "$input" | cut -d'-' -f2)

				if [ "$range_start" -ge 1 ] && [ "$range_start" -le 65535 ] && \
					[ "$range_end" -ge 1 ] && [ "$range_end" -le 65535 ] && \
					[ "$range_start" -le "$range_end" ]; then
					if echo "$current_listen_port" | grep -qE '^[0-9]+-[0-9]+$'; then
						current_range_start=$(echo "$current_listen_port" | cut -d'-' -f1)
						current_range_end=$(echo "$current_listen_port" | cut -d'-' -f2)

						if [ "$range_start" -le "$current_range_end" ] && [ "$range_end" -ge "$current_range_start" ]; then
							listen_port="$input"
						else
							echo "当前监听端口范围不在输入的范围内, 请重新输入!当前范围：${current_listen_port}"
							continue
						fi
					else
						listen_port="$input"
					fi
				else
					echo "端口范围无效, 请输入类似 3000-5000 的有效端口范围!"
					continue
				fi
			elif is_port "$input"; then
				if echo "$current_listen_port" | grep -qE '^[0-9]+-[0-9]+$'; then
					current_range_start=$(echo "$current_listen_port" | cut -d'-' -f1)
					current_range_end=$(echo "$current_listen_port" | cut -d'-' -f2)

					if [ "$input" -ge "$current_range_start" ] && [ "$input" -le "$current_range_end" ]; then
						listen_port="$input"
					else
						echo "输入的端口不在当前监听端口范围内, 请重新输入!当前范围：${current_listen_port}"
						continue
					fi
				else
					listen_port="$input"
				fi
			else
				echo "输入有误, 请输入 1~65535 之间的数字或有效的端口范围!"
				continue
			fi
		fi

		if port_using "$listen_port" && [ "$listen_port" != "$current_listen_port" ]; then
			echo "端口已被占用, 请重新输入!"
			continue
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	端口 = ${listen_port}
	---------------------------
	EOF

	[ -z "$target_addr" ] && target_addr="$D_TARGET_ADDR"
	cat >&1 <<-'EOF'
	请输入需要加速的地址
	可以输入主机名称、IPv4 地址或者 IPv6 地址
	EOF
	read -p "(默认: ${target_addr}): " input
	if [ -n "$input" ]; then
		target_addr="$input"
	fi

	input=""
	cat >&1 <<-EOF
	---------------------------
	加速地址 = ${target_addr}
	---------------------------
	EOF

	[ -z "$target_port" ] && target_port="$D_TARGET_PORT"
	while true
	do
		cat >&1 <<-'EOF'
		请输入需要加速的端口 [1~65535]
		EOF
		read -p "(默认: ${target_port}): " input
		if [ -n "$input" ]; then
			if is_port "$input"; then
				if [ "$input" = "$listen_port" ]; then
					echo "加速端口不能和 Kcptun 端口一致!"
					continue
				fi

				target_port="$input"
			else
				echo "输入有误, 请输入 1~65535 之间的数字!"
				continue
			fi
		fi

		if [ "$target_addr" = "127.0.0.1" ] && ! port_using "$target_port"; then
			read -p "当前没有软件使用此端口, 确定加速此端口? [y/n]: " yn
			if [ -n "$yn" ]; then
				case "$(first_character "$yn")" in
					y|Y)
						;;
					*)
						continue
						;;
				esac
			fi
		fi

		break
	done

	input=""
	yn=""
	cat >&1 <<-EOF
	---------------------------
	加速端口 = ${target_port}
	---------------------------
	EOF

	[ -z "$key" ] && key="$D_KEY"
	cat >&1 <<-'EOF'
	请设置 Kcptun 密码(key)
	该参数必须两端一致
	EOF
	read -p "(默认密码: ${key}): " input
	[ -n "$input" ] && key="$input"

	input=""
	cat >&1 <<-EOF
	---------------------------
	密码 = ${key}
	---------------------------
	EOF

	[ -z "$crypt" ] && crypt="$D_CRYPT"
	local crypt_list="aes aes-128 aes-192 salsa20 blowfish twofish cast5 3des tea xtea xor none"
	local i=0
	cat >&1 <<-'EOF'
	请选择加密方式(crypt)
	强加密对 CPU 要求较高，
	如果是在路由器上配置客户端，
	请尽量选择弱加密或者不加密。
	该参数必须两端一致
	EOF
	while true
	do

		for c in $crypt_list; do
			i=$(expr $i + 1)
			echo "(${i}) ${c}"
		done

		read -p "(默认: ${crypt}) 请选择 [1~$i]: " input
		if [ -n "$input" ]; then
			if is_number "$input" && [ $input -ge 1 ] && [ $input -le $i ]; then
				crypt=$(echo "$crypt_list" | cut -d' ' -f ${input})
			else
				echo "请输入有效数字 1~$i!"
				i=0
				continue
			fi
		fi
		break
	done

	input=""
	i=0
	cat >&1 <<-EOF
	-----------------------------
	加密方式 = ${crypt}
	-----------------------------
	EOF

	[ -z "$mode" ] && mode="$D_MODE"
	local mode_list="normal fast fast2 fast3 manual"
	i=0
	cat >&1 <<-'EOF'
	请选择加速模式(mode)
	加速模式和发送窗口大小共同决定了流量的损耗大小
	如果加速模式选择“手动(manual)”，
	将进入手动档隐藏参数的设置。
	EOF
	while true
	do

		for m in $mode_list; do
			i=$(expr $i + 1)
			echo "(${i}) ${m}"
		done

		read -p "(默认: ${mode}) 请选择 [1~$i]: " input
		if [ -n "$input" ]; then
			if is_number "$input" && [ $input -ge 1 ] && [ $input -le $i ]; then
				mode=$(echo "$mode_list" | cut -d ' ' -f ${input})
			else
				echo "请输入有效数字 1~$i!"
				i=0
				continue
			fi
		fi
		break
	done

	input=""
	i=0
	cat >&1 <<-EOF
	---------------------------
	加速模式 = ${mode}
	---------------------------
	EOF

	if [ "$mode" = "manual" ]; then
		set_manual_parameters
	else
		nodelay=""
		interval=""
		resend=""
		nc=""
	fi

	[ -z "$mtu" ] && mtu="$D_MTU"
	while true
	do
		cat >&1 <<-'EOF'
		请设置 UDP 数据包的 MTU (最大传输单元)值
		EOF
		read -p "(默认: ${mtu}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			mtu=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	MTU = ${mtu}
	---------------------------
	EOF

	[ -z "$sndwnd" ] && sndwnd="$D_SNDWND"
	while true
	do
		cat >&1 <<-'EOF'
		请设置发送窗口大小(sndwnd)
		发送窗口过大会浪费过多流量
		EOF
		read -p "(数据包数量, 默认: ${sndwnd}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			sndwnd=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	sndwnd = ${sndwnd}
	---------------------------
	EOF

	[ -z "$rcvwnd" ] && rcvwnd="$D_RCVWND"
	while true
	do
		cat >&1 <<-'EOF'
		请设置接收窗口大小(rcvwnd)
		EOF
		read -p "(数据包数量, 默认: ${rcvwnd}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			rcvwnd=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	rcvwnd = ${rcvwnd}
	---------------------------
	EOF

	[ -z "$datashard" ] && datashard="$D_DATASHARD"
	while true
	do
		cat >&1 <<-'EOF'
		请设置前向纠错 datashard (每组数据分片数, 通常 1~64)
		值越大单组数据越多, 吞吐更高, 但重组延迟与内存占用也更高
		推荐: 常规网络保持 10; 延迟敏感场景可适当降到 6~8
		该参数必须两端一致
		EOF
		read -p "(默认: ${datashard}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -lt 1 ]; then
				echo "输入有误, 请输入大于等于1的数字!"
				continue
			fi

			datashard=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	datashard = ${datashard}
	---------------------------
	EOF

	[ -z "$parityshard" ] && parityshard="$D_PARITYSHARD"
	while true
	do
		cat >&1 <<-'EOF'
		请设置前向纠错 parityshard (每组冗余分片数)
		0 表示关闭 FEC; 值越大抗丢包越强, 但流量开销越高
		流量开销约为 (datashard + parityshard) / datashard 倍
		参考: 丢包<1% 用 0~1; 1%~5% 用 2~3; 5%~10% 用 4~6; >10% 用 8~10
		该参数必须两端一致
		EOF
		read -p "(默认: ${parityshard}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -lt 0 ]; then
				echo "输入有误, 请输入大于等于0的数字!"
				continue
			fi

			parityshard=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	parityshard = ${parityshard}
	---------------------------
	EOF

	[ -z "$dscp" ] && dscp="$D_DSCP"
	while true
	do
		cat >&1 <<-'EOF'
		请设置差分服务代码点(DSCP)
		EOF
		read -p "(默认: ${dscp}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -lt 0 ]; then
				echo "输入有误, 请输入大于等于0的数字!"
				continue
			fi

			dscp=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	DSCP = ${dscp}
	---------------------------
	EOF

	[ -z "$nocomp" ] && nocomp="$D_NOCOMP"
	while true
	do
		cat >&1 <<-'EOF'
		是否关闭数据压缩?
		对CPU性能有损耗
		如果是文本类数据，可设手动开启
		如果是数据套壳，则默认保持关闭直接
		EOF
		read -p "(默认: ${nocomp}) [y/n]: " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					nocomp='true'
					;;
				n|N)
					nocomp='false'
					;;
				*)
					echo "输入有误，请重新输入!"
					continue
					;;
			esac
		fi
		break
	done

	yn=""
	cat >&1 <<-EOF
	---------------------------
	nocomp = ${nocomp}
	---------------------------
	EOF

	[ -z "$quiet" ] && quiet="$D_QUIET"
	while true
	do
		cat >&1 <<-'EOF'
		是否屏蔽 open/close 日志输出?
		EOF
		read -p "(默认: ${quiet}) [y/n]: " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					quiet='true'
					;;
				n|N)
					quiet='false'
					;;
				*)
					echo "输入有误，请重新输入!"
					continue
					;;
			esac
		fi
		break
	done

	yn=""
	cat >&1 <<-EOF
	---------------------------
	quiet = ${quiet}
	---------------------------
	EOF

	[ -z "$tcp" ] && tcp="$D_TCP"
	while true
	do
		cat >&1 <<-'EOF'
		是否使用 TCP 传输
		EOF
		read -p "(默认: ${tcp}) [y/n]: " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					tcp='true'
					;;
				n|N)
					tcp='false'
					;;
				*)
					echo "输入有误，请重新输入!"
					continue
					;;
			esac
		fi
		break
	done

	if [ "$tcp" = "true" ]; then
		run_user="root"
	fi

	yn=""
	cat >&1 <<-EOF
	---------------------------
	tcp = ${tcp}
	---------------------------
	EOF

	unset_snmp() {
		snmplog=""
		snmpperiod=""
		cat >&1 <<-EOF
		---------------------------
		不记录 SNMP 日志
		---------------------------
		EOF
	}

	cat >&1 <<-EOF
	是否记录 SNMP 日志?
	EOF
	read -p "(默认: 否) [y/n]: " yn
	if [ -n "$yn" ]; then
		case "$(first_character "$yn")" in
			y|Y)
				set_snmp
				;;
			n|N|*)
				unset_snmp
				;;
		esac
		yn=""
	else
		unset_snmp
	fi

	[ -z "$pprof" ] && pprof="$D_PPROF"
	while true
	do
		cat >&1 <<-'EOF'
		是否开启 pprof 性能监控?
		地址: http://IP:6060/debug/pprof/
		EOF
		read -p "(默认: ${pprof}) [y/n]: " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					pprof='true'
					;;
				n|N)
					pprof='false'
					;;
				*)
					echo "输入有误，请重新输入!"
					continue
					;;
			esac
		fi
		break
	done

	yn=""
	cat >&1 <<-EOF
	---------------------------
	pprof = ${pprof}
	---------------------------
	EOF

	unset_hidden_parameters() {
		acknodelay=""
		sockbuf=""
		smuxbuf=""
		keepalive=""
		streambuf=""
		smuxver=""
		cat >&1 <<-EOF
		---------------------------
		不配置隐藏参数
		---------------------------
		EOF
	}

	cat >&1 <<-'EOF'
	基础参数设置完成，是否设置额外的隐藏参数?
	通常情况下保持默认即可，不用额外设置
	EOF
	read -p "(默认: 否) [y/n]: " yn
	if [ -n "$yn" ]; then
		case "$(first_character "$yn")" in
			y|Y)
				set_hidden_parameters
				;;
			n|N|*)
				unset_hidden_parameters
				;;
		esac
	else
		unset_hidden_parameters
	fi

	# 监听低端口或使用 TCP 时需要 root 权限
	if echo "$listen_port" | grep -qE '^[0-9]+-[0-9]+$'; then
		range_start=$(echo "$listen_port" | cut -d'-' -f1)
		range_end=$(echo "$listen_port" | cut -d'-' -f2)

		if [ "$range_start" -le 1024 ] || [ "$range_end" -le 1024 ]; then
			run_user="root"
		fi
	elif is_port "$listen_port" && [ "$listen_port" -le 1024 ]; then
		run_user="root"
	fi

	echo "配置完成。"
	any_key_to_continue
}

set_snmp() {
	snmplog="$(get_current_file 'snmp')"

	local input=""
	[ -z "$snmpperiod" ] && snmpperiod="$D_SNMPPERIOD"
	while true
	do
		cat >&1 <<-'EOF'
		请设置 SNMP 记录间隔时间 snmpperiod
		EOF
		read -p "(默认: ${snmpperiod}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -lt 0 ]; then
				echo "输入有误, 请输入大于等于0的数字!"
				continue
			fi

			snmpperiod=$input
		fi
		break
	done

	cat >&1 <<-EOF
	---------------------------
	snmplog = ${snmplog}
	snmpperiod = ${snmpperiod}
	---------------------------
	EOF
}

set_manual_parameters() {
	echo "开始配置手动参数..."
	local input=""
	local yn=""

	[ -z "$nodelay" ] && nodelay="$D_NODELAY"
	while true
	do
		cat >&1 <<-'EOF'
		是否启用 nodelay 模式?
		(0) 不启用
		(1) 启用
		EOF
		read -p "(默认: ${nodelay}) [0/1]: " input
		if [ -n "$input" ]; then
			case "$(first_character "$input")" in
				1)
					nodelay=1
					;;
				0|*)
					nodelay=0
					;;
				*)
					echo "输入有误，请重新输入!"
					continue
					;;
			esac
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	nodelay = ${nodelay}
	---------------------------
	EOF

	[ -z "$interval" ] && interval="$D_INTERVAL"
	while true
	do
		cat >&1 <<-'EOF'
		请设置协议内部工作的 interval
		EOF
		read -p "(单位: ms, 默认: ${interval}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			interval=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	interval = ${interval}
	---------------------------
	EOF

	[ -z "$resend" ] && resend="$D_RESEND"
	while true
	do
		cat >&1 <<-'EOF'
		是否启用快速重传模式(resend)?
		(0) 不启用
		(1) 启用
		(2) 2次ACK跨越将会直接重传
		EOF
		read -p "(默认: ${resend}) 请选择 [0~2]: " input
		if [ -n "$input" ]; then
			case "$(first_character "$input")" in
				0)
					resend=0
					;;
				1)
					resend=1
					;;
				2)
					resend=2
					;;
				*)
					echo "输入有误，请重新输入!"
					continue
					;;
			esac
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	resend = ${resend}
	---------------------------
	EOF

	[ -z "$nc" ] && nc="$D_NC"
	while true
	do
		cat >&1 <<-'EOF'
		是否关闭流控(nc)?
		(0) 关闭
		(1) 开启
		EOF
		read -p "(默认: ${nc}) [0/1]: " input
		if [ -n "$input" ]; then
			case "$(first_character "$input")" in
				0)
					nc=0
					;;
				1)
					nc=1
					;;
				*)
					echo "输入有误，请重新输入!"
					continue
					;;
			esac
		fi
		break
	done
	cat >&1 <<-EOF
	---------------------------
	nc = ${nc}
	---------------------------
	EOF
}

set_hidden_parameters() {
	echo "开始设置隐藏参数..."
	local input=""
	local yn=""

	[ -z "$acknodelay" ] && acknodelay="$D_ACKNODELAY"
	while true
	do
		cat >&1 <<-'EOF'
		是否启用 acknodelay 模式?
		EOF
		read -p "(默认: ${acknodelay}) [y/n]: " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					acknodelay="true"
					;;
				n|N)
					acknodelay="false"
					;;
				*)
					echo "输入有误，请重新输入!"
					continue
					;;
			esac
		fi
		break
	done

	yn=""
	cat >&1 <<-EOF
	---------------------------
	acknodelay = ${acknodelay}
	---------------------------
	EOF

	[ -z "$sockbuf" ] && sockbuf="$D_SOCKBUF"
	while true
	do
		cat >&1 <<-'EOF'
		请设置 UDP 收发缓冲区大小(sockbuf)
		EOF
		read -p "(单位: MB, 默认: $(expr ${sockbuf} / 1024 / 1024)): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			sockbuf=$(expr $input \* 1024 \* 1024)
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	sockbuf = ${sockbuf}
	---------------------------
	EOF

	[ -z "$smuxbuf" ] && smuxbuf="$D_SMUXBUF"
	while true
	do
		cat >&1 <<-'EOF'
		请设置 de-mux 缓冲区大小(smuxbuf)
		EOF
		read -p "(单位: MB, 默认: $(expr ${smuxbuf} / 1024 / 1024)): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			smuxbuf=$(expr $input \* 1024 \* 1024)
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	smuxbuf = ${smuxbuf}
	---------------------------
	EOF

	[ -z "$keepalive" ] && keepalive="$D_KEEPALIVE"
	while true
	do
		cat >&1 <<-'EOF'
		请设置 Keepalive 的间隔时间
		EOF
		read -p "(单位: s, 默认值: ${keepalive}, 前值: 5): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			keepalive=$input
		fi
		break
	done

	cat >&1 <<-EOF
	---------------------------
	keepalive = ${keepalive}
	---------------------------
	EOF

	[ -z "$smuxver" ] && smuxver="$D_SMUXVER"
	while true
	do
		cat >&1 <<-'EOF'
		请设置 smux 的版本
		EOF
		read -p "(1,2, 默认值: ${smuxver}, 老版本默认1，新版本默认2): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			smuxver=$input
		fi
		break
	done

	cat >&1 <<-EOF
	---------------------------
	$smuxver = ${smuxver}
	---------------------------
	EOF

	[ -z "$streambuf" ] && streambuf="$D_STREAMBUF"
	while true
	do
		cat >&1 <<-'EOF'
		请设置 streambuf 大小，官方文档介绍本值不宜过大
		EOF
		read -p "(单位: MB, 默认: $(expr ${streambuf} / 1024 / 1024)): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "输入有误, 请输入大于0的数字!"
				continue
			fi

			streambuf=$(expr $input \* 1024 \* 1024)
		fi
		break
	done

	cat >&1 <<-EOF
	---------------------------
	streambuf = ${streambuf}
	---------------------------
	EOF
}

# 生成 Kcptun 服务端配置文件
gen_kcptun_config() {
	mk_file_dir() {
		local dir=""
		dir="$(dirname "$1")"
		local mod=$2

		if [ ! -d "$dir" ]; then
			(
				set -x
				mkdir -p "$dir"
			)
		fi

		if [ -n "$mod" ]; then
			chmod $mod "$dir"
		fi
	}

	local config_file=""
	config_file="$(get_current_file 'config')"
	local service_file=""
	service_file="$(get_current_file 'service')"

	mk_file_dir "$config_file"
	mk_file_dir "$service_file"

	if [ -n "$snmplog" ]; then
		mk_file_dir "$snmplog" '777'
	fi

	if ( echo "$listen_addr" | grep -q ":" ); then
		listen_addr="[${listen_addr}]"
	fi

	if ( echo "$target_addr" | grep -q ":" ); then
		target_addr="[${target_addr}]"
	fi

	cat > "$config_file"<<-EOF
	{
	  "listen": "${listen_addr}:${listen_port}",
	  "target": "${target_addr}:${target_port}",
	  "key": "${key}",
	  "crypt": "${crypt}",
	  "mode": "${mode}",
	  "mtu": ${mtu},
	  "sndwnd": ${sndwnd},
	  "rcvwnd": ${rcvwnd},
	  "datashard": ${datashard},
	  "parityshard": ${parityshard},
	  "dscp": ${dscp},
	  "nocomp": ${nocomp},
	  "quiet": ${quiet},
	  "tcp": ${tcp}
	}
	EOF

	write_configs_to_file() {
		install_jq
		local k; local v

		local json=""
		json="$(cat "$config_file")"
		for k in "$@"; do
			v="$(eval echo "\$$k")"

			if [ -n "$v" ]; then
				if is_number "$v" || [ "$v" = "false" ] || [ "$v" = "true" ]; then
					json="$(echo "$json" | $JQ_BIN ".$k=$v")"
				else
					json="$(echo "$json" | $JQ_BIN ".$k=\"$v\"")"
				fi
			fi
		done

		if [ -n "$json" ] && [ "$json" != "$(cat "$config_file")" ]; then
			echo "$json" >"$config_file"
		fi
	}

	write_configs_to_file "snmplog" "snmpperiod" "pprof" "acknodelay" "nodelay" \
		"interval" "resend" "nc" "sockbuf" "smuxbuf" "keepalive" "streambuf" "smuxver"

	# 以最终写入的配置为准重新推断运行用户，兼容手动编辑配置的场景
	if [ -f "$config_file" ]; then
		run_user="$(get_instance_run_user "$current_instance_id")"
	fi

	if ! grep -q "^${run_user}:" '/etc/passwd'; then
		(
			set -x
			useradd -U -s '/usr/sbin/nologin' -d '/nonexistent' "$run_user" 2>/dev/null
		)
	fi

	# 旧版由 root 托管的日志文件需要交还给运行用户
	local log_file=""
	log_file="$(get_current_file 'log')"
	if [ -f "$log_file" ] && [ "$run_user" != "root" ]; then
		chown "$run_user" "$log_file" 2>/dev/null || true
	fi

	gen_service_file
}

# 将 30000-35000 形式的端口转换为防火墙工具要求的范围写法
to_range_port() {
	echo "$1" | sed 's/-/:/'
}

# 检测可用的防火墙管理工具，优先使用发行版默认工具
detect_firewall_tool() {
	if command_exists firewall-cmd; then
		echo 'firewalld'
	elif command_exists ufw; then
		echo 'ufw'
	elif command_exists iptables; then
		echo 'iptables'
	fi
}

# firewalld 放行端口，不启动或重启防火墙
set_firewall_firewalld() {
	local new_port="${listen_port}/udp"
	local old_port=""
	[ -n "$current_listen_port" ] && old_port="${current_listen_port}/udp"

	if ! firewall-cmd --state >/dev/null 2>&1; then
		# 防火墙未运行：端口本身已可用，只尝试写入永久配置，不启动服务
		if firewall-cmd --permanent --zone=public --add-port="$new_port" >/dev/null 2>&1; then
			cat >&1 <<-EOF
			firewalld 当前未运行，已写入永久规则 ${new_port}，未启动防火墙。
			EOF
		else
			cat >&1 <<-EOF
			firewalld 当前未运行，跳过端口放行（端口可直接使用），也不会启动防火墙。
			如需预置规则，可在防火墙启动后执行:
			    firewall-cmd --permanent --zone=public --add-port=${new_port}
			    firewall-cmd --reload
			EOF
		fi
		return 0
	fi

	if [ -n "$old_port" ] && [ "$old_port" != "$new_port" ]; then
		firewall-cmd --permanent --zone=public --remove-port="$old_port" >/dev/null 2>&1 || true
		firewall-cmd --zone=public --remove-port="$old_port" >/dev/null 2>&1 || true
	fi

	if firewall-cmd --permanent --zone=public --add-port="$new_port" >/dev/null 2>&1 && \
		firewall-cmd --zone=public --add-port="$new_port" >/dev/null 2>&1; then
		cat >&1 <<-EOF
		已在 firewalld 放行 UDP 端口: ${new_port}
		EOF
	else
		cat >&1 <<-EOF
		警告: 自动添加 firewalld 规则失败
		如有必要, 请手动添加端口 ${new_port} 的防火墙规则:
		    firewall-cmd --permanent --zone=public --add-port=${new_port}
		    firewall-cmd --reload
		EOF
	fi
}

# ufw 放行端口，不启用或重启防火墙
set_firewall_ufw() {
	local new_port=""
	new_port="$(to_range_port "$listen_port")/udp"
	local old_port=""
	[ -n "$current_listen_port" ] && old_port="$(to_range_port "$current_listen_port")/udp"

	local ufw_active="false"
	if ufw status 2>/dev/null | grep -q 'Status: active'; then
		ufw_active="true"
	fi

	if [ -n "$old_port" ] && [ "$old_port" != "$new_port" ]; then
		ufw delete allow "$old_port" >/dev/null 2>&1 || true
	fi

	if ufw allow "$new_port" >/dev/null 2>&1; then
		if [ "$ufw_active" = "true" ]; then
			cat >&1 <<-EOF
			已在 ufw 放行 UDP 端口: ${new_port}
			EOF
		else
			cat >&1 <<-EOF
			ufw 当前未启用，已写入放行规则 ${new_port}，未启用或重启防火墙。
			EOF
		fi
	else
		cat >&1 <<-EOF
		警告: 自动添加 ufw 规则失败
		如有必要, 请手动执行: ufw allow ${new_port}
		EOF
	fi
}

# iptables 放行端口，仅在服务已运行时保存规则，不启动或重启防火墙
set_firewall_iptables() {
	local new_port=""
	new_port="$(to_range_port "$listen_port")"
	local old_port=""
	[ -n "$current_listen_port" ] && old_port="$(to_range_port "$current_listen_port")"

	if [ -n "$old_port" ] && [ "$old_port" != "$new_port" ]; then
		iptables -D INPUT -p udp --dport "$old_port" -j ACCEPT >/dev/null 2>&1 || true
	fi

	if ! iptables -C INPUT -p udp --dport "$new_port" -j ACCEPT >/dev/null 2>&1; then
		if ! iptables -I INPUT -p udp --dport "$new_port" -j ACCEPT >/dev/null 2>&1; then
			cat >&1 <<-EOF
			警告: 自动添加 iptables 规则失败
			如有必要, 请手动添加端口 ${new_port} 的防火墙规则:
			    iptables -I INPUT -p udp --dport ${new_port} -j ACCEPT
			EOF
			return 0
		fi
	fi

	local iptables_running="false"
	if service iptables status >/dev/null 2>&1; then
		iptables_running="true"
	elif command_exists systemctl && systemctl is-active iptables >/dev/null 2>&1; then
		iptables_running="true"
	fi

	if [ "$iptables_running" = "true" ]; then
		service iptables save >/dev/null 2>&1 || true
		cat >&1 <<-EOF
		已在 iptables 放行 UDP 端口: ${new_port}，并已保存规则。
		EOF
	elif command_exists netfilter-persistent; then
		netfilter-persistent save >/dev/null 2>&1 || true
		cat >&1 <<-EOF
		已在 iptables 放行 UDP 端口: ${new_port}，并已通过 netfilter-persistent 保存。
		EOF
	else
		cat >&1 <<-EOF
		已在 iptables 放行 UDP 端口: ${new_port}（临时规则，重启后可能失效）
		iptables 服务未运行，脚本不会启动或重启防火墙。
		如需持久化，请安装 iptables-persistent 或手动执行 service iptables save。
		EOF
	fi
}

# 设置防火墙开放端口
# 自动适配 firewalld / ufw / iptables，且不会启动或重启已关闭的防火墙
set_firewall() {
	local tool=""
	tool="$(detect_firewall_tool)"

	case "$tool" in
		firewalld)
			set_firewall_firewalld
			;;
		ufw)
			set_firewall_ufw
			;;
		iptables)
			set_firewall_iptables
			;;
		*)
			cat >&1 <<-EOF
			未检测到 firewall-cmd / ufw / iptables，跳过防火墙配置。
			如需放行，请手动开放 UDP 端口: ${listen_port}
			EOF
			;;
	esac
}

# 选择一个实例
select_instance() {
	if [ "$(get_instance_count)" -gt 1 ]; then
		cat >&1 <<-'EOF'
		当前有多个 Kcptun 实例 (按最后修改时间排序):
		EOF

		local files=""
		files="$(list_instance_files)"
		local i=0
		local array=""
		local id=""
		for file in $files; do
			id="$(echo "$file" | sed -e 's/^kcptun//' -e 's/\.service$//')"
			array="${array}${id}#"

			i=$(expr $i + 1)
			echo "(${i}) kcptun${id}"
		done

		local sel=""
		while true
		do
			read -p "请选择 [1~${i}]: " sel
			if [ -n "$sel" ]; then
				if ! is_number "$sel" || [ $sel -lt 1 ] || [ $sel -gt $i ]; then
					cat >&2 <<-EOF
					请输入有效数字 1~${i}!
					EOF
					continue
				fi
			else
				cat >&2 <<-EOF
				请输入不能为空！
				EOF
				continue
			fi

			current_instance_id=$(echo "$array" | cut -d '#' -f ${sel})
			break
		done
	fi
}

# 通过当前服务端环境获取 Kcptun 服务端文件名
get_kcptun_server_file() {
	if [ -z "$file_suffix" ]; then
		get_arch
	fi

	echo "${KCPTUN_INSTALL_DIR}/server_$file_suffix"
}

# 计算新实例的 ID
get_new_instance_id() {
	if [ -f "$(get_service_file_path '')" ]; then
		local i=2
		while [ -f "$(get_service_file_path "$i")" ]
		do
			i=$(expr $i + 1)
		done
		echo "$i"
	fi
}

# 获取已安装的 Kcptun 版本
get_installed_version() {
	local server_file=""
	server_file="$(get_kcptun_server_file)"

	if [ -f "$server_file" ]; then
		if [ ! -x "$server_file" ]; then
			chmod a+x "$server_file"
		fi

		echo "$(${server_file} -v 2>/dev/null | awk '{print $3}')"
	fi
}

# 统一 Kcptun 版本号格式，8 位纯数字版本自动补 v 前缀
normalize_kcptun_tag() {
	local tag="$1"
	if [ -n "$tag" ] && is_number "$tag" && [ ${#tag} -eq 8 ]; then
		echo "v${tag}"
	else
		echo "$tag"
	fi
}

# 启动时提示可用更新（脚本 / Kcptun），仅提示，网络不可用时静默跳过
check_update_notice() {
	local notices=""

	local shell_content=""
	shell_content="$(https_get_quick "$SHELL_VERSION_INFO_URL" 2>/dev/null | sed -r 's/(\\r)?\\n/#br#/g')"
	if [ -n "$shell_content" ]; then
		local remote_shell=""
		remote_shell="$(echo "$shell_content" | grep -oE '"shell_version"[[:space:]]*:[[:space:]]*[0-9]+' | head -n 1 | grep -oE '[0-9]+$')"
		if is_number "$remote_shell" && [ "$remote_shell" -gt "$SHELL_VERSION" ]; then
			notices="${notices}  - 安装脚本: v${SHELL_VERSION} -> v${remote_shell}\n"
		fi
	fi

	local kcptun_content=""
	kcptun_content="$(https_get_quick "$KCPTUN_LATEST_RELEASE_URL" 2>/dev/null | sed -r 's/(\\r)?\\n/#br#/g')"
	if [ -n "$kcptun_content" ]; then
		local remote_tag=""
		remote_tag="$(echo "$kcptun_content" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')"
		local local_tag=""
		local remote_tag_normalized=""
		local_tag="$(normalize_kcptun_tag "$(get_installed_version)")"
		remote_tag_normalized="$(normalize_kcptun_tag "$remote_tag")"
		if [ -n "$remote_tag_normalized" ] && [ -n "$local_tag" ] && [ "$remote_tag_normalized" != "$local_tag" ]; then
			notices="${notices}  - Kcptun:   ${local_tag} -> ${remote_tag_normalized}\n"
		fi
	fi

	if [ -n "$notices" ]; then
		cat >&1 <<-EOF

		========================================================
		发现可用更新:
		$(printf '%b' "$notices")
		可在菜单中选择 (4) 更新菜单，或运行 sh $0 update
		========================================================
		EOF
	fi
}

# 加载当前选择实例的配置文件
load_instance_config() {
	local config_file=""
	config_file="$(get_current_file 'config')"

	if [ ! -s "$config_file" ]; then
		cat >&2 <<-'EOF'
		实例配置文件不存在或为空, 请检查!
		EOF
		exit 1
	fi

	local config_content=""
	config_content="$(cat ${config_file})"

	if [ -z "$(get_json_string "$config_content" '.listen')" ]; then
		cat >&2 <<-EOF
		实例配置文件存在错误, 请检查!
		配置文件路径: ${config_file}
		EOF
		exit 1
	fi

	local lines=""
	lines="$(get_json_string "$config_content" 'to_entries | map("\(.key)=\(.value | @sh)") | .[]')"

	OLDIFS=$IFS
	IFS=$(printf '\n')
	for line in $lines; do
		eval "$line"
	done
	IFS=$OLDIFS

	if [ -n "$listen" ]; then
		listen_port="$(echo "$listen" | rev | cut -d ':' -f1 | rev)"
		listen_addr="$(echo "$listen" | sed "s/:${listen_port}$//" | grep -oE '[0-9a-fA-F\.:]*')"
		listen=""
	fi
	if [ -n "$target" ]; then
		target_port="$(echo "$target" | rev | cut -d ':' -f1 | rev)"
		target_addr="$(echo "$target" | sed "s/:${target_port}$//" | grep -oE '[0-9a-fA-F\.:]*')"
		target=""
	fi

	if [ -n "$listen_port" ]; then
		current_listen_port="$listen_port"
	fi
}

# 显示服务端 Kcptun 版本，和客户端文件的下载地址
show_version_and_client_url() {
	local version=""
	version="$(get_installed_version)"
	if [ -n "$version" ]; then
		cat >&1 <<-EOF

		当前安装的 Kcptun 版本为: ${version}
		EOF
	fi

	if [ -n "$kcptun_release_html_url" ]; then
		cat >&1 <<-EOF
		请自行前往:
		  ${kcptun_release_html_url}
		手动下载客户端文件
		EOF
	fi
}

# 显示当前选择实例的信息
show_current_instance_info() {
	local server_ip=""
	server_ip="$(get_server_ip)"

	printf '服务器IP: \033[41;37m %s \033[0m\n' "$server_ip"
	printf '端口: \033[41;37m %s \033[0m\n' "$listen_port"
	printf '加速地址: \033[41;37m %s:%s \033[0m\n' "$target_addr" "$target_port"

	show_configs() {
		local k; local v
		for k in "$@"; do
			v="$(eval echo "\$$k")"
			if [ -n "$v" ]; then
				printf '%s: \033[41;37m %s \033[0m\n' "$k" "$v"
			fi
		done
	}

	show_configs "key" "crypt" "mode" "mtu" "sndwnd" "rcvwnd" "datashard" \
		"parityshard" "dscp" "nocomp" "quiet" "tcp" "nodelay" "interval" "resend" \
		"nc" "acknodelay" "sockbuf" "smuxbuf" "keepalive" "streambuf" "smuxver"

	show_version_and_client_url

	install_jq
	local client_config=""

	# 这里输出的是客户端所使用的配置信息
	# 客户端的 *remoteaddr* 端口号为服务端的 *listen_port*
	# 客户端的 *localaddr* 端口号被设置为了服务端的加速端口
	client_config="$(cat <<-EOF
	{
	  "localaddr": ":${target_port}",
	  "remoteaddr": "${server_ip}:${listen_port}",
	  "key": "${key}"
	}
	EOF
	)"

	gen_client_configs() {
		local k; local v
		for k in "$@"; do
			if [ "$k" = "sndwnd" ]; then
				v="$rcvwnd"
			elif [ "$k" = "rcvwnd" ]; then
				v="$sndwnd"
			else
				v="$(eval echo "\$$k")"
			fi

			if [ -n "$v" ]; then
				if is_number "$v" || [ "$v" = "true" ] || [ "$v" = "false" ]; then
					client_config="$(echo "$client_config" | $JQ_BIN -r ".${k}=${v}")"
				else
					client_config="$(echo "$client_config" | $JQ_BIN -r ".${k}=\"${v}\"")"
				fi
			fi
		done
	}

	gen_client_configs "crypt" "mode" "mtu" "sndwnd" "rcvwnd" "datashard" \
		"parityshard" "dscp" "nocomp" "quiet" "tcp" "nodelay" "interval" "resend" \
		"nc" "acknodelay" "sockbuf" "smuxbuf" "keepalive" "streambuf" "smuxver"

	cat >&1 <<-EOF

	可使用的客户端配置文件为:
	${client_config}
	EOF

	local mobile_config="key=${key}"
	gen_mobile_configs() {
		local k; local v
		for k in "$@"; do
			if [ "$k" = "sndwnd" ]; then
				v="$rcvwnd"
			elif [ "$k" = "rcvwnd" ]; then
				v="$sndwnd"
			else
				v="$(eval echo "\$$k")"
			fi

			if [ -n "$v" ]; then
				if [ "$v" = "false" ]; then
					continue
				elif [ "$v" = "true" ]; then
					mobile_config="${mobile_config};${k}"
				else
					mobile_config="${mobile_config};${k}=${v}"
				fi
			fi
		done
	}

	gen_mobile_configs "crypt" "mode" "mtu" "sndwnd" "rcvwnd" "datashard" \
		"parityshard" "dscp" "nocomp" "quiet" "tcp" "nodelay" "interval" "resend" \
		"nc" "acknodelay" "sockbuf" "smuxbuf" "keepalive" "streambuf" "smuxver"

	cat >&1 <<-EOF

	手机端参数可以使用:
	  ${mobile_config}

	EOF
}

do_install() {
	check_root
	disable_selinux
	installed_check
	set_kcptun_config
	install_deps
	install_kcptun
	install_service_manager
	gen_kcptun_config
	set_firewall
	apply_service_config
	enable_instance_service "$current_instance_id"

	cat >&1 <<-EOF

	恭喜! Kcptun 服务端安装成功。
	EOF

	show_current_instance_info

	cat >&1 <<-EOF
	Kcptun 安装目录: ${KCPTUN_INSTALL_DIR}

	已将 Kcptun 服务加入开机自启,
	服务管理方式: ${SERVICE_BACKEND}

	更多使用说明: ${0} help
	
	EOF
}

# 卸载操作
do_uninstall() {
	check_root
	cat >&1 <<-'EOF'
	你选择了卸载 Kcptun 服务端
	EOF
	any_key_to_continue
	echo "正在停止 Kcptun 服务并清理配置..."

	detect_service_backend

	local file=""
	local instance_id=""
	for file in $(list_instance_files); do
		instance_id="$(echo "$file" | sed -e 's/^kcptun//' -e 's/\.service$//')"
		stop_instance_service "$instance_id"
		disable_instance_service "$instance_id"
	done

	(
		set -x
		rm -f "$SYSTEMD_UNIT_DIR"/kcptun*.service
		rm -f "$SYSV_INIT_DIR"/kcptun*
		rm -f /var/run/kcptun*.pid
		rm -rf "$KCPTUN_INSTALL_DIR"
		rm -rf "$KCPTUN_LOG_DIR"
	)
	reload_service_manager

	# 旧版 Supervisor 配置清理
	if [ -d "$LEGACY_SUPERVISOR_DIR" ] && \
		ls "$LEGACY_SUPERVISOR_DIR"/kcptun*.conf >/dev/null 2>&1; then
		cat >&1 <<-EOF
		检测到旧版 Supervisor 配置:
		  ${LEGACY_SUPERVISOR_DIR}/kcptun*.conf
		是否一并删除这些旧配置?
		EOF

		local yn=""
		read -p "(默认: 不删除) 请选择 [y/n]: " yn
		case "$(first_character "$yn")" in
			y|Y)
				if command_exists supervisorctl; then
					local conf=""
					for conf in "$LEGACY_SUPERVISOR_DIR"/kcptun*.conf; do
						supervisorctl stop "$(basename "$conf" .conf)" >/dev/null 2>&1 || true
					done
				fi
				(
					set -x
					rm -f "$LEGACY_SUPERVISOR_DIR"/kcptun*.conf
				)
				;;
		esac
	fi

	cat >&1 <<-'EOF'
	卸载完成, 欢迎再次使用。
	EOF
}

# 迁移旧版 Supervisor 部署到 systemd / SysVinit
do_migrate() {
	check_root

	if ! is_installed; then
		cat >&2 <<-EOF
		未检测到已安装的 Kcptun，无法迁移。
		请先运行 $0 install 安装。
		EOF
		exit 1
	fi

	if ! has_legacy_instances; then
		if [ "$(get_instance_count)" -gt 0 ]; then
			cat >&1 <<-EOF
			当前已是 ${SERVICE_BACKEND} 部署，共 $(get_instance_count) 个实例，
			无需迁移，也不会重复执行迁移。
			EOF
		else
			cat >&1 <<-EOF
			未检测到旧版 Supervisor 实例，当前没有需要迁移的内容。
			EOF
		fi
		return 0
	fi

	if [ -s "$MIGRATE_MARKER" ]; then
		cat >&1 <<-EOF
		检测到迁移标记 v$(cat "$MIGRATE_MARKER")，但仍有 Supervisor 实例未迁移，
		将继续处理剩余实例。
		EOF
	fi

	migrate_legacy_instances
}

# 仅检查脚本与 Kcptun 是否有新版本，不执行更新
do_check() {
	check_root

	cat >&1 <<-EOF
	正在检查脚本与 Kcptun 更新...
	EOF

	local found_update="false"

	if get_shell_version_info; then
		if [ "$new_shell_version" -gt "$SHELL_VERSION" ]; then
			found_update="true"
			cat >&1 <<-EOF
			发现脚本更新: v${SHELL_VERSION} -> v${new_shell_version}
			更新说明:
			$(printf '%s\n' "$shell_change_log")
			EOF

			if [ -n "$shell_release_url" ]; then
				cat >&1 <<-EOF
				发布页面: ${shell_release_url}
				EOF
			fi
		fi

		if [ "$new_config_version" -gt "$CONFIG_VERSION" ]; then
			found_update="true"
			cat >&1 <<-EOF
			发现配置模板更新: v${CONFIG_VERSION} -> v${new_config_version}
			EOF
		fi

		if [ "$new_init_version" -gt "$INIT_VERSION" ]; then
			found_update="true"
			cat >&1 <<-EOF
			发现服务文件更新: v${INIT_VERSION} -> v${new_init_version}
			EOF
		fi
	else
		cat >&2 <<-EOF
		检查脚本更新失败，请检查网络或 version.json 地址。
		EOF
	fi

	if is_installed; then
		detect_service_backend

		if has_legacy_instances; then
			found_update="true"
			cat >&1 <<-EOF
			检测到旧版 Supervisor 部署，可执行 '$0 migrate' 迁移到 ${SERVICE_BACKEND}，无需重新配置。
			EOF
		else
			cat >&1 <<-EOF
			当前已是 ${SERVICE_BACKEND} 部署，无需迁移。
			EOF
		fi

		echo "正在检查 Kcptun 版本..."
		if get_kcptun_version_info; then
			local cur_tag_name=""
			cur_tag_name="$(get_installed_version)"
			if [ -n "$kcptun_release_tag_name" ] && \
				[ "$kcptun_release_tag_name" != "$cur_tag_name" ]; then
				found_update="true"
				cat >&1 <<-EOF
				发现 Kcptun 新版本 ${kcptun_release_tag_name} (当前: ${cur_tag_name})
				EOF

				if [ "$kcptun_release_prerelease" = "true" ]; then
					cat >&1 <<-EOF
					注意: 该版本为预览版, 请谨慎更新。
					EOF
				fi
			fi
		fi
	else
		cat >&1 <<-EOF
		Kcptun 未安装, 跳过主程序版本检查。
		EOF
	fi

	if [ "$found_update" = "false" ]; then
		cat >&1 <<-EOF
		当前脚本与 Kcptun 均为最新版本。
		EOF
	fi

	cat >&1 <<-EOF

	提示: 使用 $0 update 可执行全部更新。
	EOF
}

# 更新
# 更新安装脚本（含配置模板与服务文件版本）
# 脚本本体更新完成后直接退出，避免继续使用旧进程逻辑
# 返回值: 0 = 已执行更新或迁移, 1 = 获取版本信息失败, 2 = 无可用更新
update_script_component() {
	if ! get_shell_version_info false; then
		cat >&2 <<-EOF
		获取安装脚本版本信息失败，请检查网络后重试。
		EOF
		return 1
	fi

	local shell_path="$0"
	local changed="false"

	if [ "$new_shell_version" -gt "$SHELL_VERSION" ]; then
		cat >&1 <<-EOF
		发现一键安装脚本更新: v${SHELL_VERSION} -> v${new_shell_version}
		更新说明:
		$(printf '%s\n' "$shell_change_log")
		EOF

		if [ -n "$shell_release_url" ]; then
			cat >&1 <<-EOF
			发布页面: ${shell_release_url}
			EOF
		fi

		any_key_to_continue

		# 先下载到临时文件，校验通过后再替换，避免更新失败导致脚本丢失
		local new_shell_path="${shell_path}.new"
		download_file "$new_shell_url" "$new_shell_path" "$new_shell_sha256"
		chmod a+x "$new_shell_path"

		mv -f "$shell_path" "$shell_path".bak
		mv -f "$new_shell_path" "$shell_path"

		sed -i -r "s/^CONFIG_VERSION=[0-9]+/CONFIG_VERSION=${CONFIG_VERSION}/" "$shell_path"
		sed -i -r "s/^INIT_VERSION=[0-9]+/INIT_VERSION=${INIT_VERSION}/" "$shell_path"
		rm -f "$shell_path".bak

		clear
		cat >&1 <<-EOF
		安装脚本已更新到 v${new_shell_version}。
		请重新运行 'sh $0 update'，以完成配置模板与服务文件的更新。
		EOF

		exit 0
	fi

	if [ "$new_config_version" -gt "$CONFIG_VERSION" ]; then
		cat >&1 <<-EOF
		发现 Kcptun 配置更新, 版本号: v${new_config_version}
		更新说明:
		$(printf '%s\n' "$config_change_log")
		需要重新设置 Kcptun
		EOF
		any_key_to_continue

		instance_reconfig

		sed -i "s/^CONFIG_VERSION=${CONFIG_VERSION}/CONFIG_VERSION=${new_config_version}/" \
			"$shell_path"
		changed="true"
	fi

	if [ "$new_init_version" -gt "$INIT_VERSION" ]; then
		cat >&1 <<-EOF
		发现服务启动脚本文件更新, 版本号: v${new_init_version}
		更新说明:
		$(printf '%s\n' "$init_change_log")
		EOF

		any_key_to_continue

		regenerate_service_files
		sed -i "s/^INIT_VERSION=${INIT_VERSION}/INIT_VERSION=${new_init_version}/" \
			"$shell_path"
		changed="true"
	fi

	if [ "$changed" = "true" ]; then
		return 0
	fi

	return 2
}

# 更新 Kcptun 主程序
# 返回值: 0 = 已更新, 1 = 获取版本信息失败, 2 = 无可用更新
update_kcptun_component() {
	echo "开始获取 Kcptun 版本信息..."
	if ! get_kcptun_version_info "" false; then
		cat >&2 <<-EOF
		获取 Kcptun 版本信息失败，请检查网络后重试。
		EOF
		return 1
	fi

	local cur_tag_name=""
	cur_tag_name="$(normalize_kcptun_tag "$(get_installed_version)")"

	if [ -z "$kcptun_release_tag_name" ] || [ "$kcptun_release_tag_name" = "$cur_tag_name" ]; then
		cat >&1 <<-EOF
		未发现 Kcptun 更新，当前版本: ${cur_tag_name}
		EOF
		return 2
	fi

	cat >&1 <<-EOF
	发现 Kcptun 新版本 ${kcptun_release_tag_name}
	$([ "$kcptun_release_prerelease" = "true" ] && printf "\033[41;37m 注意: 该版本为预览版, 请谨慎更新 \033[0m")
	更新说明:
	$(printf '%s\n' "$kcptun_release_body")
	EOF
	any_key_to_continue

	install_kcptun
	apply_service_config

	show_version_and_client_url
	return 0
}

# 更新菜单：分别管理安装脚本与 Kcptun 的更新
do_update_menu() {
	pre_ckeck

	while true
	do
		local shell_status="获取失败"
		local kcptun_status="获取失败"
		local shell_available="false"
		local kcptun_available="false"

		if get_shell_version_info false; then
			if is_number "$new_shell_version" && [ "$new_shell_version" -gt "$SHELL_VERSION" ]; then
				shell_status="v${SHELL_VERSION} -> v${new_shell_version}"
				shell_available="true"
			else
				shell_status="v${SHELL_VERSION} (已是最新)"
			fi
		fi

		if get_kcptun_version_info "" false; then
			local cur_tag_name=""
			cur_tag_name="$(normalize_kcptun_tag "$(get_installed_version)")"
			if [ -n "$kcptun_release_tag_name" ] && [ "$kcptun_release_tag_name" != "$cur_tag_name" ]; then
				kcptun_status="${cur_tag_name} -> ${kcptun_release_tag_name}"
				kcptun_available="true"
			else
				kcptun_status="${cur_tag_name} (已是最新)"
			fi
		fi

		cat >&1 <<-EOF

		==================== 更新管理 ====================
		安装脚本: ${shell_status}
		Kcptun:    ${kcptun_status}
		--------------------------------------------------
		(1) 更新安装脚本
		(2) 更新 Kcptun
		(3) 全部更新
		(4) 返回
		EOF

		local sel=""
		read -p "(默认: 4) 请选择 [1~4]: " sel
		[ -z "$sel" ] && sel="4"

		case "$(first_character "$sel")" in
			1)
				if [ "$shell_available" != "true" ]; then
					echo "当前没有可用的安装脚本更新。"
					continue
				fi
				update_script_component
				;;
			2)
				if [ "$kcptun_available" != "true" ]; then
					echo "当前没有可用的 Kcptun 更新。"
					continue
				fi
				local kcptun_rc=0
				update_kcptun_component
				kcptun_rc=$?
				# 更新失败时停留一次便于查看错误；无可用更新时直接回到菜单
				if [ "$kcptun_rc" != "2" ]; then
					any_key_to_continue
				fi
				;;
			3)
				local kcptun_rc=0
				local script_rc=0
				update_kcptun_component
				kcptun_rc=$?
				update_script_component
				script_rc=$?
				# 两个组件都没有可更新内容时不再要求按键，直接回到更新菜单
				if [ "$kcptun_rc" != "2" ] || [ "$script_rc" != "2" ]; then
					any_key_to_continue
				fi
				;;
			*)
				return 0
				;;
		esac
	done
}

# 更新（命令行入口：先更新 Kcptun，最后更新脚本）
do_update() {
	pre_ckeck

	cat >&1 <<-EOF
	你选择了更新, 正在开始操作...
	EOF

	update_kcptun_component
	update_script_component

	# 仅表示流程已执行完毕，避免把组件的“无可用更新”返回值当成失败退出码
	return 0
}

# 添加实例
instance_add() {
	pre_ckeck

	cat >&1 <<-'EOF'
	你选择了添加实例, 正在开始操作...
	EOF
	current_instance_id="$(get_new_instance_id)"

	set_kcptun_config
	gen_kcptun_config
	set_firewall
	apply_service_config
	enable_instance_service "$current_instance_id"

	cat >&1 <<-EOF
	恭喜, 实例 kcptun${current_instance_id} 添加成功!
	EOF
	show_current_instance_info
}

# 删除实例
instance_del() {
	pre_ckeck

	if [ -n "$1" ]; then
		if is_number "$1"; then
			if [ "$1" != "1" ]; then
				current_instance_id="$1"
			fi
		else
			cat >&2 <<-EOF
			参数有误, 请使用 $0 del <id>
			<id> 为实例ID, 当前共有 $(get_instance_count) 个实例
			EOF

			exit 1
		fi
	fi

	cat >&1 <<-EOF
	你选择了删除实例 kcptun${current_instance_id}
	注意: 实例删除后无法恢复
	EOF
	any_key_to_continue

	# 获取实例的服务文件
	local service_file=""
	service_file="$(get_current_file 'service')"
	if [ ! -f "$service_file" ]; then
		echo "你选择的实例 kcptun${current_instance_id} 不存在!"
		exit 1
	fi

	local current_config_file=""
	current_config_file="$(get_current_file 'config')"
	local current_log_file=""
	current_log_file="$(get_current_file 'log')"
	local current_snmp_log_file=""
	current_snmp_log_file="$(get_current_file 'snmp')"

	stop_instance_service "$current_instance_id"
	disable_instance_service "$current_instance_id"

	(
		set -x
		rm -f "$service_file" \
			"$current_config_file" \
			"$current_log_file" \
			"$current_snmp_log_file"
	)

	reload_service_manager

	cat >&1 <<-EOF
	实例 kcptun${current_instance_id} 删除成功!
	EOF
}

# 显示实例信息
instance_show() {
	pre_ckeck

	if [ -n "$1" ]; then
		if is_number "$1"; then
			if [ "$1" != "1" ]; then
				current_instance_id="$1"
			fi
		else
			cat >&2 <<-EOF
			参数有误, 请使用 $0 show <id>
			<id> 为实例ID, 当前共有 $(get_instance_count) 个实例
			EOF

			exit 1
		fi
	fi

	echo "你选择了查看实例 kcptun${current_instance_id} 的配置, 正在读取..."

	load_instance_config

	echo "实例 kcptun${current_instance_id} 的配置信息如下:"
	show_current_instance_info
}

# 显示实例日志
instance_log() {
	pre_ckeck

	if [ -n "$1" ]; then
		if is_number "$1"; then
			if [ "$1" != "1" ]; then
				current_instance_id="$1"
			fi
		else
			cat >&2 <<-EOF

			参数有误, 请使用 $0 log <id>
			<id> 为实例ID, 当前共有 $(get_instance_count) 个实例
			EOF

			exit 1
		fi
	fi

	echo "你选择了查看实例 kcptun${current_instance_id} 的日志, 正在读取..."

	local log_file=""
	log_file="$(get_current_file 'log')"

	if [ -f "$log_file" ]; then
		cat >&1 <<-EOF
		实例 kcptun${current_instance_id} 的日志信息如下:
		注: 日志实时刷新, 按 Ctrl+C 退出日志查看
		EOF
		tail -n 20 -f "$log_file"
	else
		cat >&2 <<-EOF
		未找到实例 kcptun${current_instance_id} 的日志文件...
		EOF
		exit 1
	fi
}

# 重新配置实例
instance_reconfig() {
	pre_ckeck

	if [ -n "$1" ]; then
		if is_number "$1"; then
			if [ "$1" != "1" ]; then
				current_instance_id="$1"
			fi
		else
			cat >&2 <<-EOF
			参数有误, 请使用 $0 reconfig <id>
			<id> 为实例ID, 当前共有 $(get_instance_count) 个实例
			EOF

			exit 1
		fi
	fi

	cat >&1 <<-EOF
	你选择了重新配置实例 kcptun${current_instance_id}, 正在开始操作...
	EOF

	if [ ! -f "$(get_current_file 'service')" ]; then
		cat >&2 <<-EOF
		你选择的实例 kcptun${current_instance_id} 不存在!
		EOF
		exit 1
	fi

	local sel=""
	cat >&1 <<-'EOF'
	请选择操作:
	(1) 重新配置实例所有选项
	(2) 直接修改实例配置文件
	EOF
	read -p "(默认: 1) 请选择: " sel
	echo
	[ -z "$sel" ] && sel="1"

	case "$(first_character "$sel")" in
		2)
			echo "正在打开配置文件, 请手动修改..."
			local config_file=""
			config_file="$(get_current_file 'config')"
			edit_config_file() {
				if [ ! -f "$config_file" ]; then
					return 1
				fi

				if command_exists nano; then
					nano "$config_file"
				elif command_exists vim; then
					vim "$config_file"
				elif command_exists vi; then
					vi "$config_file"
				elif command_exists gedit; then
					gedit "$config_file"
				else
					echo "未找到可用的编辑器, 正在进入全新配置..."
					return 1
				fi

				load_instance_config
			}

			if ! edit_config_file; then
				set_kcptun_config
			fi
			;;
		1|*)
			load_instance_config
			set_kcptun_config
			;;
	esac

	gen_kcptun_config
	set_firewall

	apply_service_config

	cat >&1 <<-EOF

	恭喜, Kcptun 服务端配置已更新!
	EOF
	show_current_instance_info
}

#手动安装
manual_install() {
	pre_ckeck

	cat >&1 <<-'EOF'
	你选择了自定义版本安装, 正在开始操作...
	EOF

	local tag_name="$1"

	while true
	do
		if [ -z "$tag_name" ]; then
			cat >&1 <<-'EOF'
			请输入你想安装的 Kcptun 版本的完整 TAG
			EOF
			read -p "(例如: v20160904): " tag_name
			if [ -z "$tag_name" ]; then
				echo "输入无效, 请重新输入!"
				continue
			fi
		fi

		if [ "$tag_name" = "SNMP_Milestone" ]; then
			echo "不支持此版本, 请重新输入!"
			tag_name=""
			continue
		fi

		local version_num=""
		version_num=$(echo "$tag_name" | grep -oE "[0-9]+" || "0")
		if [ ${#version_num} -eq 8 ] && [ $version_num -le 20160826 ]; then
			echo "不支持安装 v20160826 及以前版本"
			tag_name=""
			continue
		fi

		echo "正在获取信息，请稍候..."
		get_kcptun_version_info "$tag_name"
		if [ "$?" != "0" ]; then
			cat >&2 <<-EOF
			未找到对应版本下载地址 (TAG: ${tag_name}), 请重新输入!
			你可以前往:
			  ${KCPTUN_TAGS_URL}
			查看所有可用 TAG
			EOF
			tag_name=""
			continue
		else
			cat >&1 <<-EOF
			已找到 Kcptun 版本信息, TAG: ${tag_name}
			EOF
			any_key_to_continue

			install_kcptun "$tag_name"
			apply_service_config
			show_version_and_client_url
			break
		fi
	done
}

pre_ckeck() {
	check_root

	# 旧版 Supervisor 实例先自动迁移，保证 show/log/reconfig 等命令可用
	if is_installed && has_legacy_instances; then
		migrate_legacy_instances
	fi

	if ! is_installed; then
		cat >&2 <<-EOF
		错误: 检测到你还没有安装 Kcptun，
		或者 Kcptun 程序文件已损坏，
		请运行脚本来重新安装 Kcptun 服务端。
		EOF

		exit 1
	fi
}

# 监测是否安装了 kcptun
is_installed() {
	if [ -d '/usr/share/kcptun' ]; then
		cat >&1 <<-EOF
		检测发现你由旧版升级到了新版
		新版中将默认安装目录设置为了 ${KCPTUN_INSTALL_DIR}
		脚本会自动将文件从旧版目录 /usr/share/kcptun
		移动到新版目录 ${KCPTUN_INSTALL_DIR}
		EOF
		any_key_to_continue
		(
			set -x
			cp -rf '/usr/share/kcptun' "$KCPTUN_INSTALL_DIR" && \
				rm -rf '/usr/share/kcptun'
		)
	fi

	if [ -d "$KCPTUN_INSTALL_DIR" ] && [ -n "$(get_installed_version)" ]; then
		if [ "$(get_instance_count)" -gt 0 ] || has_legacy_instances; then
			return 0
		fi
	fi

	return 1
}

# 检查是否已经安装
installed_check() {
	local instance_count=""

	# 旧版 Supervisor 实例先自动迁移，避免用户被要求重新配置
	if is_installed && has_legacy_instances; then
		migrate_legacy_instances
	fi

	instance_count="$(get_instance_count)"
	if is_installed && [ "$instance_count" -gt 0 ]; then
		cat >&1 <<-EOF
		检测到你已安装 Kcptun 服务端, 已配置的实例个数为 ${instance_count} 个
		EOF

		check_update_notice

		while true
		do
			cat >&1 <<-'EOF'
			请选择你希望的操作:
			(1) 覆盖安装
			(2) 重新配置
			(3) 添加实例(多端口)
			(4) 更新菜单
			(5) 查看配置
			(6) 查看日志输出
			(7) 自定义版本安装
			(8) 删除实例
			(9) 完全卸载
			(10) 退出脚本
			EOF
			read -p "(默认: 1) 请选择 [1~10]: " sel
			[ -z "$sel" ] && sel=1

			case $sel in
				1)
					echo "开始覆盖安装 Kcptun 服务端..."
					load_instance_config
					return 0
					;;
				2)
					select_instance
					instance_reconfig
					;;
				3)
					instance_add
					;;
				4)
					do_update_menu
					continue
					;;
				5)
					select_instance
					instance_show
					;;
				6)
					select_instance
					instance_log
					;;
				7)
					manual_install
					;;
				8)
					select_instance
					instance_del
					;;
				9)
					do_uninstall
					;;
				10)
					;;
				*)
					echo "输入有误, 请输入有效数字 1~10!"
					continue
					;;
			esac

			exit 0
		done
	fi
}

action=${1:-"install"}
case "$action" in
	install|uninstall|update|check|migrate)
		do_${action}
		;;
	add|reconfig|show|log|del)
		instance_${action} "$2"
		;;
	manual)
		manual_install "$2"
		;;
	help)
		usage 0
		;;
	*)
		usage 1
		;;
esac
