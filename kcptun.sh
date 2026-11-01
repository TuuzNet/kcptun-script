#!/bin/sh

: <<-'EOF'
Fixed
EOF

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 版本信息，请勿修改
# =================
SHELL_VERSION=45
CONFIG_VERSION=9
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

# 客户端参数默认值，这些键只写进客户端配置，服务端进程会忽略
D_CONN=1
D_AUTOEXPIRE=0
D_AUTOEXPIREMAX=0
D_SCAVENGETTL=0
D_KEEPALIVETOLERANCE=2

# 客户端专用参数列表：服务端二进制不认识这些键，不得写进 server-config*.json
CLIENT_PARAM_KEYS="conn autoexpire autoexpiremax scavengettl keepalivetolerance"

# 开关型参数：向导里选“否”就是明确要关闭，写入时要从配置里删掉而不是保留旧值
DELETE_ON_WRITE_KEYS=""
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
	    clientconf <id>  生成客户端配置(可设置 conn / autoexpire 等客户端本地参数)
	    losstest <id>    丢包测试(需客户端同版本配合)

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

# 判断输入内容是否为整数，允许一个前导负号
# expr "-1" + 1 的结果是 0，退出码为 1，所以 is_number 会把 -1 判成非数字，
# 而 autoexpire=-1 是合法的配置值，写入 JSON 时必须保持数字而非字符串
is_int() {
	local number="${1#-}"
	case "$number" in
		'' | *[!0-9]*)
			return 1
			;;
	esac
	return 0
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
# 仅对 GitHub API 请求附带 token，避免把凭据发送给第三方镜像
github_auth_header() {
	local url="$1"
	if [ -n "${GITHUB_TOKEN:-}" ]; then
		case "$url" in
			https://api.github.com/*)
				printf 'Authorization: Bearer %s' "$GITHUB_TOKEN"
				;;
		esac
	fi
}

# 探测 URL 的 HTTP 状态码，失败时用于给出可读原因
https_probe_status() {
	local url=""
	url="$(url_with_proxy "$1")"
	local auth=""
	auth="$(github_auth_header "$url")"
	local status=""

	if command_exists curl; then
		if [ -n "$auth" ]; then
			status="$(curl -s -o /dev/null -w '%{http_code}' --insecure --max-time 10 -H "User-Agent: kcptun-script/${SHELL_VERSION}" -H "$auth" "$url" 2>/dev/null)"
		else
			status="$(curl -s -o /dev/null -w '%{http_code}' --insecure --max-time 10 -H "User-Agent: kcptun-script/${SHELL_VERSION}" "$url" 2>/dev/null)"
		fi
	elif command_exists wget; then
		if [ -n "$auth" ]; then
			status="$(wget --server-response --spider --no-check-certificate --timeout=10 --header="User-Agent: kcptun-script/${SHELL_VERSION}" --header="$auth" "$url" 2>&1 | awk '/HTTP\//{code=$2} END{print code}')"
		else
			status="$(wget --server-response --spider --no-check-certificate --timeout=10 --header="User-Agent: kcptun-script/${SHELL_VERSION}" "$url" 2>&1 | awk '/HTTP\//{code=$2} END{print code}')"
		fi
	fi
	printf '%s' "$status"
}

https_get() {
	local url=""
	url="$(url_with_proxy "$1")"
	local auth=""
	auth="$(github_auth_header "$url")"

	if command_exists wget; then
		if [ -n "$auth" ]; then
			wget -qO- --no-check-certificate --header="User-Agent: kcptun-script/${SHELL_VERSION}" --header="$auth" "$url"
		else
			wget -qO- --no-check-certificate --header="User-Agent: kcptun-script/${SHELL_VERSION}" "$url"
		fi
	elif command_exists curl; then
		if [ -n "$auth" ]; then
			curl -fsSL --insecure -H "User-Agent: kcptun-script/${SHELL_VERSION}" -H "$auth" "$url"
		else
			curl -fsSL --insecure -H "User-Agent: kcptun-script/${SHELL_VERSION}" "$url"
		fi
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
		wget -qO- --no-check-certificate --tries=1 --timeout=5 --header="User-Agent: kcptun-script/${SHELL_VERSION}" "$url"
	elif command_exists curl; then
		curl -fsSL --insecure --max-time 5 -H "User-Agent: kcptun-script/${SHELL_VERSION}" "$url"
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

		# 去掉 CRLF 中的 CR，保留换行，jq 可直接解析
		content="$(https_get "$url" | tr -d '\r')"

		if [ "$?" != "0" ] || [ -z "$content" ]; then
			retry=$(expr $retry + 1)
			get_network_content
		fi
	}

	get_network_content || return 1
	printf '%s' "$content"
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
		str="$(printf '%s' "$content" | $JQ_BIN -r "$selector" 2>/dev/null)"

		if [ -n "$str" ] && [ -n "$regex" ]; then
			str="$(printf '%s' "$str" | grep -oE "$regex")"
		fi
	fi
	printf '%s' "$str"
}

# 获取当前实例的文件路径，传入参数：
# * config: kcptun 服务端配置文件
# * clientconf: 客户端参数旁路文件，只用于生成客户端配置，服务端进程不读取
# * log: kcptun 日志文件路径
# * snmp: kcptun snmp 日志文件路径
# * service: 实例的服务文件路径（systemd unit 或 init 脚本）
get_current_file() {
	case "$1" in
		config)
			printf '%s/server-config%s.json' "$KCPTUN_INSTALL_DIR" "$current_instance_id"
			;;
		clientconf)
			printf '%s/client-params%s.json' "$KCPTUN_INSTALL_DIR" "$current_instance_id"
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
# 根据 HTTP 状态给出 Kcptun 版本获取失败的可读原因
kcptun_api_error_hint() {
	local request_version="$1"
	local url="$KCPTUN_LATEST_RELEASE_URL"
	[ -n "$request_version" ] && url="${KCPTUN_RELEASES_API}?per_page=100"

	local status=""
	status="$(https_probe_status "$url")"
	case "$status" in
		403|429)
			printf 'GitHub API 限流(HTTP %s)，请稍后重试或设置 GITHUB_TOKEN' "$status"
			;;
		5??)
			printf 'GitHub API 服务异常(HTTP %s)' "$status"
			;;
		200)
			printf 'GitHub API 响应为空或解析失败'
			;;
		''|000)
			printf '无法访问 api.github.com，请检查网络或配置 KCPTUN_RELEASES_API 镜像'
			;;
		*)
			printf 'GitHub API 返回 HTTP %s' "$status"
			;;
	esac
}

get_kcptun_version_info() {
	local request_version="$1"
	local fatal="${2:-true}"
	kcptun_version_error=""

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
		kcptun_version_error="$(kcptun_api_error_hint "$request_version")"
		return 1
	fi

	if [ -z "$file_suffix" ]; then
		get_arch
	fi

	kcptun_release_tag_name="$(get_json_string "$version_content" '.tag_name')"

	local server_asset="server_${file_suffix}"
	local url_selector=".assets[] | select(.name == \"${server_asset}\") | .browser_download_url"
	kcptun_release_download_url="$(get_json_string "$version_content" "$url_selector")"

	if [ -z "$kcptun_release_download_url" ]; then
		kcptun_version_error="Release ${kcptun_release_tag_name:-未知} 中缺少 server_${file_suffix} 资产"
		return 1
	fi

	local checksums_selector=".assets[] | select(.name == \"checksums.txt\") | .browser_download_url"
	kcptun_release_checksums_url="$(get_json_string "$version_content" "$checksums_selector")"
	kcptun_release_name="$(get_json_string "$version_content" '.name')"
	kcptun_release_prerelease="$(get_json_string "$version_content" '.prerelease')"
	kcptun_release_publish_time="$(get_json_string "$version_content" '.published_at')"
	kcptun_release_html_url="$(get_json_string "$version_content" '.html_url')"

	local body_content="$(get_json_string "$version_content" '.body')"
	local body="$(printf '%s' "$body_content" | grep -vE '(^```)|(^>)|(^[[:space:]]*$)')"

	# 更新说明中去掉长串哈希，避免刷屏
	kcptun_release_body="$(printf '%s' "$body" | grep -vE "[0-9a-zA-Z]{32,}")"

	return 0
}

# 获取可安装的 Kcptun 版本列表
# 输出格式: TAG<TAB>发布时间<TAB>是否预览版, 每行一个版本, 按发布时间倒序
# 参数: 最多返回的版本数量(默认 30)
list_kcptun_versions() {
	local limit="${1:-30}"
	local json_content=""
	json_content="$(get_content "${KCPTUN_RELEASES_API}?per_page=100" false)"
	if [ -z "$json_content" ]; then
		return 1
	fi

	local list=""
	list="$(get_json_string "$json_content" \
		".[] | select(.draft | not) | [.tag_name, (.published_at // \"\"), (.prerelease | tostring)] | @tsv")"
	if [ -z "$list" ]; then
		return 1
	fi

	# 过滤掉脚本不支持安装的版本, 并限制显示数量
	printf '%s\n' "$list" | awk -F '\t' -v limit="$limit" '
		{
			num = $1
			gsub(/[^0-9]/, "", num)
			if ($1 == "SNMP_Milestone") next
			if (length(num) == 8 && num + 0 <= 20160826) next
			if (count >= limit) next
			count++
			print $0
		}'
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

	printf '%s' "$checksum_content" | \
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
		# SNMP 是开关语义：选否就应当真的关掉，不能因为合并而保留旧值
		DELETE_ON_WRITE_KEYS="snmplog snmpperiod"
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
	smuxver = ${smuxver}
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

# 设置客户端参数（只用于生成客户端配置，由 save_client_configs 存在旁路文件里，
# 不写进服务端配置；只在 instance_clientconf 里调用）
set_client_parameters() {
	echo "开始设置客户端参数..."
	local input=""

	[ -z "$conn" ] && conn="$D_CONN"
	while true
	do
		cat >&1 <<-'EOF'
		请设置客户端到服务端的 KCP 连接数（也就是本地 UDP 端口数）
		EOF
		read -p "(默认: ${conn}): " input
		if [ -n "$input" ]; then
			if ! is_int "$input" || [ "$input" -lt 1 ]; then
				echo "输入有误, 请输入大于0的整数!"
				continue
			fi

			conn=$input
		fi
		break
	done

	cat >&1 <<-EOF
	---------------------------
	conn = ${conn}
	---------------------------
	EOF

	[ -z "$autoexpire" ] && autoexpire="$D_AUTOEXPIRE"
	while true
	do
		cat >&1 <<-EOF
		请设置客户端端口轮换策略 (autoexpire)：
		  0  : 固定端口，不轮换
		  -1 : 全自动模式，永不按时钟轮换，只有端口被判定堵塞时才切换全部端口
		  >0 : 每隔指定秒数轮换一次端口
		EOF
		read -p "(默认: ${autoexpire}): " input
		if [ -n "$input" ]; then
			if ! is_int "$input" || [ "$input" -lt -1 ]; then
				echo "输入有误, 请输入 -1 或不小于0的整数!"
				continue
			fi

			autoexpire=$input
		fi
		break
	done

	if [ "$autoexpire" = "-1" ]; then
		[ -z "$keepalivetolerance" ] && keepalivetolerance="$D_KEEPALIVETOLERANCE"
		while true
		do
			cat >&1 <<-'EOF'
			全自动模式：连续多少个心跳没有应答就把端口判定为堵塞 (keepalivetolerance)
			检测窗口 = keepalive x keepalivetolerance，必须小于内置的30秒会话超时
			EOF
			read -p "(默认: ${keepalivetolerance}): " input
			if [ -n "$input" ]; then
				if ! is_int "$input" || [ "$input" -lt 1 ]; then
					echo "输入有误, 请输入大于0的整数!"
					continue
				fi

				keepalivetolerance=$input
			fi
			break
		done

		# 全自动模式不按时钟轮换；存成显式 0 而不是留空，否则旁路文件里
		# 会残留上次定时模式留下的值，生成的客户端配置看起来仍在轮换
		autoexpiremax=0
		scavengettl=0

		# 未设置隐藏参数时 keepalive 为空，按客户端默认值计算检测窗口
		local window=$(( ${keepalive:-$D_KEEPALIVE} * keepalivetolerance ))
		if [ "$window" -ge 30 ]; then
			cat >&1 <<-EOF
			警告：keepalive(${keepalive:-$D_KEEPALIVE}) x keepalivetolerance(${keepalivetolerance}) = ${window}s，
			      大于等于内置的 30 秒会话超时，会话会先被超时关闭。请调小 keepalive 或 keepalivetolerance。
			EOF
			any_key_to_continue
		fi

		if [ "$datashard" = "0" ] || [ "$parityshard" = "0" ]; then
			cat >&1 <<-EOF
			警告：未开启 FEC(datashard/parityshard)，存活探测不可用，
			      全自动模式将只按心跳静默判定端口堵塞，误判概率上升。
			EOF
			any_key_to_continue
		fi

		cat >&1 <<-EOF
		---------------------------
		autoexpire = ${autoexpire}
		keepalivetolerance = ${keepalivetolerance}
		---------------------------
		EOF
	else
		keepalivetolerance=""

		if [ "$autoexpire" -gt 0 ]; then
			[ -z "$autoexpiremax" ] && autoexpiremax="$D_AUTOEXPIREMAX"
			while true
			do
				cat >&1 <<-EOF
				请设置端口轮换周期的随机上限 (autoexpiremax)，0 表示不随机
				EOF
				read -p "(默认: ${autoexpiremax}): " input
				if [ -n "$input" ]; then
					if ! is_int "$input" || [ "$input" -lt 0 ]; then
						echo "输入有误, 请输入不小于0的整数!"
						continue
					fi

					autoexpiremax=$input
				fi
				break
			done

			[ -z "$scavengettl" ] && scavengettl="$D_SCAVENGETTL"
			while true
			do
				cat >&1 <<-EOF
				请设置旧连接的强制回收时限 (scavengettl)，0 表示永不强制关闭
				注意：保留旧连接会与新连接在服务端争抢同一地址，可能导致轮换后首次连接失败
				EOF
				read -p "(默认: ${scavengettl}): " input
				if [ -n "$input" ]; then
					if ! is_int "$input" || [ "$input" -lt 0 ]; then
						echo "输入有误, 请输入不小于0的整数!"
						continue
					fi

					scavengettl=$input
				fi
				break
			done
		else
			autoexpiremax=""
			scavengettl=""
		fi

		cat >&1 <<-EOF
		---------------------------
		autoexpire = ${autoexpire}
		autoexpiremax = ${autoexpiremax}
		scavengettl = ${scavengettl}
		---------------------------
		EOF
	fi

	cat >&1 <<-EOF
	---------------------------
	客户端参数设置完成
	---------------------------
	EOF
}

# 从服务端配置里移除旧版本误写的客户端键
#
# conn / autoexpire / scavengettl / keepalivetolerance 只属于客户端，服务端二进制
# 虽然会用 json.Decode 忽略未知键而不报错，但服务端配置里出现 autoexpire 会让人
# 以为这台服务端在做端口轮换，所以每次生成配置都顺手清理一次。
purge_client_keys_from_server_config() {
	install_jq

	local config_file=""
	config_file="$(get_current_file 'config')"
	[ -s "$config_file" ] || return 0

	local filter=""
	local k
	for k in $CLIENT_PARAM_KEYS; do
		if [ -z "$filter" ]; then
			filter=".${k}"
		else
			filter="${filter},.${k}"
		fi
	done

	local cleaned=""
	cleaned="$(cat "$config_file" | $JQ_BIN "del(${filter})" 2>/dev/null)"
	if [ -n "$cleaned" ] && [ "$cleaned" != "$(cat "$config_file")" ]; then
		echo "$cleaned" >"$config_file"
	fi
}

# 把客户端参数存进旁路文件 client-params<id>.json
#
# 这些参数只用于生成客户端配置，不属于服务端配置；早期版本曾把它们直接写进
# server-config*.json，所以这里也一并清理残留。
# 基线沿用已有的旁路文件，只覆盖本次真正给出的键，跟脚本对其他可选参数的处理一致：
# 选「不设置」等于保持原值不变，而不是把它们抹掉。
save_client_configs() {
	install_jq

	local client_file=""
	client_file="$(get_current_file 'clientconf')"

	local client_json="{}"
	if [ -s "$client_file" ]; then
		client_json="$(cat "$client_file")"
	fi

	local k; local v
	for k in $CLIENT_PARAM_KEYS; do
		v="$(eval echo "\$$k")"
		[ -z "$v" ] && continue

		if is_int "$v"; then
			client_json="$(echo "$client_json" | $JQ_BIN ".${k}=${v}")"
		else
			client_json="$(echo "$client_json" | $JQ_BIN ".${k}=\"${v}\"")"
		fi
	done

	if [ ! -f "$client_file" ] || [ "$client_json" != "$(cat "$client_file")" ]; then
		echo "$client_json" >"$client_file"
	fi

	purge_client_keys_from_server_config
}

# 读取旁路文件里的客户端参数，让向导与生成的客户端配置能延续上次的值
load_client_configs() {
	local client_file=""
	client_file="$(get_current_file 'clientconf')"
	[ -s "$client_file" ] || return 0

	install_jq

	local k; local v
	for k in $CLIENT_PARAM_KEYS; do
		v="$(cat "$client_file" | $JQ_BIN -r ".${k} // empty" 2>/dev/null)"
		[ -n "$v" ] && eval "${k}=\"${v}\""
	done
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

	local base_json=""
	base_json="$(cat <<-EOF
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
	)"

	# 已有文件时走「合并」而不是「清空重建」。
	# write_configs_to_file 只会写非空变量，如果这里把文件清零重建，上一轮配好、
	# 而本轮没重新询问到的隐藏参数（streambuf / smuxver / keepalive / sockbuf /
	# smuxbuf / acknodelay）就会静默消失——隐藏参数那一题默认是「否」，所以一跑
	# 覆盖安装或重新配置就会丢这些配置。合并让基础键以本轮答案为准，同时保留
	# 本轮没有重新给出的其他键。
	install_jq

	local merged_json=""
	if [ -s "$config_file" ]; then
		merged_json="$(echo "$base_json" | $JQ_BIN -s '.[0] * .[1]' "$config_file" - 2>/dev/null)"
	fi

	if [ -n "$merged_json" ]; then
		echo "$merged_json" >"$config_file"
	else
		echo "$base_json" >"$config_file"
	fi

	# 删除那些“本轮被明确选为关闭”的开关型参数，以及不再是 manual 模式时的
	# manual 专用参数。它们跟隐藏参数不同：“否”在这里就是关闭的意思。
	local del_keys="$DELETE_ON_WRITE_KEYS"
	if [ "$mode" != "manual" ]; then
		del_keys="$del_keys nodelay interval resend nc"
	fi

	if [ -n "$del_keys" ]; then
		local dfilter=""
		for k in $del_keys; do
			if [ -z "$dfilter" ]; then
				dfilter=".${k}"
			else
				dfilter="${dfilter},.${k}"
			fi
		done

		local deleted_json=""
		deleted_json="$(cat "$config_file" | $JQ_BIN "del(${dfilter})" 2>/dev/null)"
		if [ -n "$deleted_json" ] && [ "$deleted_json" != "$(cat "$config_file")" ]; then
			echo "$deleted_json" >"$config_file"
		fi
	fi

	write_configs_to_file() {
		install_jq
		local k; local v; local next
		local failed=""

		local json=""
		json="$(cat "$config_file")"
		for k in "$@"; do
			v="$(eval echo "\$$k")"

			[ -z "$v" ] && continue

			# 用 --arg / --argjson 传值，而不是把值拼进 jq 程序字符串
			if is_int "$v" || [ "$v" = "false" ] || [ "$v" = "true" ]; then
				next="$(printf '%s' "$json" | $JQ_BIN --argjson val "$v" ".${k}=\$val" 2>/dev/null)"
			else
				next="$(printf '%s' "$json" | $JQ_BIN --arg val "$v" ".${k}=\$val" 2>/dev/null)"
			fi

			# 关键修正：以前失败会把整个 json 变成空串，导致“一个键写失败、整批配置全部
			# 静默不写”，而向导与客户端配置 demo 读的是变量，看起来就像配好了
			if [ -z "$next" ]; then
				failed="${failed} ${k}=${v}"
				continue
			fi

			json="$next"
		done

		if [ -n "$failed" ]; then
			cat >&2 <<-EOF
			警告: 以下配置项写入 jq 失败，已跳过（其余配置正常写入）:$failed
			请反馈给脚本作者，并确认 jq 可用 (jq --version)
			EOF
			any_key_to_continue
		fi

		if [ -n "$json" ] && [ "$json" != "$(cat "$config_file")" ]; then
			echo "$json" >"$config_file"
		fi
	}

	SERVER_WRITABLE_KEYS="snmplog snmpperiod pprof acknodelay nodelay interval resend nc sockbuf smuxbuf keepalive streambuf smuxver"

	# shellcheck disable=SC2086
	write_configs_to_file $SERVER_WRITABLE_KEYS

	# 写完自校：本轮确实给过值的键必须能在文件里读到，否则就是静默丢配置，
	# 宁可在这里显式报错，也不要让用户之后自己到文件里发现
	verify_written_configs() {
		install_jq

		local k; local v; local actual
		local missing=""
		for k in $1; do
			v="$(eval echo "\$$k")"
			[ -z "$v" ] && continue

			actual="$(cat "$config_file" | $JQ_BIN -r ".${k} // empty" 2>/dev/null)"
			if [ -z "$actual" ]; then
				missing="${missing} ${k}"
			fi
		done

		if [ -n "$missing" ]; then
			cat >&2 <<-EOF
			错误: 配置写入后校验失败，以下参数在向导里给过值但没进配置文件:$missing
			配置文件: ${config_file}
			请重新运行一次配置，并把上面的信息反馈给脚本作者。
			EOF
			any_key_to_continue
		fi
	}

	# shellcheck disable=SC2086
	verify_written_configs "$SERVER_WRITABLE_KEYS"

	# 客户端参数不在服务端向导里采集，这里只清理旧版本误写进服务端配置的残留键
	purge_client_keys_from_server_config

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
	shell_content="$(https_get_quick "$SHELL_VERSION_INFO_URL" 2>/dev/null | tr -d '\r')"
	if [ -n "$shell_content" ]; then
		local remote_shell=""
		remote_shell="$(printf '%s' "$shell_content" | grep -oE '"shell_version"[[:space:]]*:[[:space:]]*[0-9]+' | head -n 1 | grep -oE '[0-9]+$')"
		if is_number "$remote_shell" && [ "$remote_shell" -gt "$SHELL_VERSION" ]; then
			notices="${notices}  - 安装脚本: v${SHELL_VERSION} -> v${remote_shell}\n"
		fi
	fi

	local kcptun_content=""
	kcptun_content="$(https_get_quick "$KCPTUN_LATEST_RELEASE_URL" 2>/dev/null | tr -d '\r')"
	if [ -n "$kcptun_content" ]; then
		local remote_tag=""
		remote_tag="$(printf '%s' "$kcptun_content" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')"
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

	# 客户端参数不在服务端配置里，从旁路文件补读
	load_client_configs
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
		"nc" "acknodelay" "sockbuf" "smuxbuf" "keepalive" "streambuf" "smuxver" \
		"conn" "autoexpire" "autoexpiremax" "scavengettl" "keepalivetolerance"

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
				if is_int "$v" || [ "$v" = "true" ] || [ "$v" = "false" ]; then
					client_config="$(echo "$client_config" | $JQ_BIN -r ".${k}=${v}")"
				else
					client_config="$(echo "$client_config" | $JQ_BIN -r ".${k}=\"${v}\"")"
				fi
			fi
		done
	}

	gen_client_configs "crypt" "mode" "mtu" "sndwnd" "rcvwnd" "datashard" \
		"parityshard" "dscp" "nocomp" "quiet" "tcp" "nodelay" "interval" "resend" \
		"nc" "acknodelay" "sockbuf" "smuxbuf" "keepalive" "streambuf" "smuxver" \
		"conn" "autoexpire" "autoexpiremax" "scavengettl" "keepalivetolerance"

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

	提示：手机端参数字符串不包含 conn / autoexpire / keepalivetolerance 等客户端高级参数，
	      需要这些参数时请使用上面生成的桌面客户端 JSON 配置文件。

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

		# 选择更新后直接执行，不再等待确认按键
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
		获取 Kcptun 版本信息失败: ${kcptun_version_error}
		请检查网络后重试。
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
		else
			kcptun_status="获取失败（${kcptun_version_error}）"
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
				update_kcptun_component
				;;
			3)
				update_kcptun_component
				update_script_component
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

# 生成客户端配置
#
# conn / autoexpire 等是客户端本地策略，服务端二进制连这些字段都没有，所以它们
# 不属于安装与重配向导：在那里问就只能把客户端状态存回服务端配置，概念和存储都
# 会错位。本入口负责当场询问、存进旁路文件，并输出可以直接拷走的客户端 JSON。
instance_clientconf() {
	pre_ckeck

	if [ -n "$1" ]; then
		if is_number "$1"; then
			if [ "$1" != "1" ]; then
				current_instance_id="$1"
			fi
		else
			cat >&2 <<-EOF
			参数有误, 请使用 $0 clientconf <id>
			<id> 为实例ID, 当前共有 $(get_instance_count) 个实例
			EOF

			exit 1
		fi
	fi

	load_instance_config

	local yn=""
	cat >&1 <<-EOF
	你选择了生成实例 kcptun${current_instance_id} 的客户端配置...

	服务端实例参数 (key / crypt / mode / FEC / 窗口等) 会自动同步到客户端，
	窗口按客户端 sndwnd = 服务端 rcvwnd 镜像。
	是否还要设置客户端本地参数 (连接数 conn 与端口轮换策略)?
	EOF
	read -p "(默认: 否, 沿用已存参数) [y/n]: " yn

	if [ -n "$yn" ]; then
		case "$(first_character "$yn")" in
			y|Y)
				set_client_parameters
				save_client_configs

				cat >&1 <<-EOF
				客户端参数已存入 $(get_current_file 'clientconf')
				EOF
				;;
			n|N|*)
				cat >&1 <<-'EOF'
				保持已存参数不变（从未设置过时为 1 条连接、固定端口）
				EOF
				;;
		esac
	else
		cat >&1 <<-'EOF'
		保持已存参数不变（从未设置过时为 1 条连接、固定端口）
		EOF
	fi

	echo "实例 kcptun${current_instance_id} 的客户端配置如下:"
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

# 将字符串安全地放进 shell 单引号中
losstest_shell_quote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# 查找本机可用的 kcptun client 二进制
losstest_find_client() {
	local bin=""
	if [ -z "$file_suffix" ]; then
		get_arch
	fi
	for bin in \
		"${KCPTUN_INSTALL_DIR}/client_${file_suffix}" \
		"${KCPTUN_INSTALL_DIR}/client" \
		"${KCPTUN_INSTALL_DIR}/kcptun-client"; do
		if [ -x "$bin" ]; then
			printf '%s' "$bin"
			return 0
		fi
	done
	if command_exists kcptun-client; then
		command -v kcptun-client
		return 0
	fi
	return 1
}

# 生成客户端丢包测试命令
# $1: 时长 $2: 强度 $3: 服务端 IP $4: client 二进制
losstest_build_command() {
	local duration="$1"
	local rate="$2"
	local server_ip="$3"
	local bin="$4"

	# 客户端发送窗口对应服务端接收窗口，反之亦然
	local c_sndwnd="${rcvwnd:-$D_RCVWND}"
	local c_rcvwnd="${sndwnd:-$D_SNDWND}"
	local cmd=""

	cmd="${bin} -losstest -losstest-duration ${duration} -losstest-rate ${rate}"
	cmd="${cmd} -remoteaddr $(losstest_shell_quote "${server_ip}:${listen_port}")"
	cmd="${cmd} -key $(losstest_shell_quote "${key:-$D_KEY}")"
	cmd="${cmd} -crypt ${crypt:-$D_CRYPT} -mode ${mode:-$D_MODE} -mtu ${mtu:-$D_MTU}"
	cmd="${cmd} -sndwnd ${c_sndwnd} -rcvwnd ${c_rcvwnd}"
	cmd="${cmd} -datashard ${datashard:-$D_DATASHARD} -parityshard ${parityshard:-$D_PARITYSHARD}"
	cmd="${cmd} -smuxver ${smuxver:-$D_SMUXVER}"
	cmd="${cmd} -nodelay ${nodelay:-$D_NODELAY} -interval ${interval:-$D_INTERVAL} -resend ${resend:-$D_RESEND} -nc ${nc:-$D_NC}"
	cmd="${cmd} -sockbuf ${sockbuf:-$D_SOCKBUF} -smuxbuf ${smuxbuf:-$D_SMUXBUF} -streambuf ${streambuf:-$D_STREAMBUF} -keepalive ${keepalive:-$D_KEEPALIVE}"
	if [ "${acknodelay:-$D_ACKNODELAY}" = 'true' ]; then
		cmd="${cmd} -acknodelay"
	fi
	if [ "${nocomp:-$D_NOCOMP}" = 'true' ]; then
		cmd="${cmd} -nocomp"
	fi
	if [ "${tcp:-$D_TCP}" = 'true' ]; then
		cmd="${cmd} -tcp"
	fi
	cmd="${cmd} -quiet"
	printf '%s\n' "$cmd"
}

# 丢包测试入口
losstest_run() {
	local arg_id="$1"

	pre_ckeck

	if [ -n "$arg_id" ]; then
		if ! is_number "$arg_id"; then
			cat >&2 <<-EOF
			参数有误, 请使用 $0 losstest <id>
			<id> 为实例ID, 当前共有 $(get_instance_count) 个实例
			EOF
			exit 1
		fi
		if [ "$arg_id" != "1" ]; then
			current_instance_id="$arg_id"
		fi
		if [ ! -f "$(get_current_file 'config')" ]; then
			cat >&2 <<-EOF
			实例 kcptun${current_instance_id} 不存在!
			EOF
			exit 1
		fi
	else
		select_instance
	fi

	load_instance_config

	local ds="${datashard:-$D_DATASHARD}"
	local ps="${parityshard:-$D_PARITYSHARD}"
	if [ "$ds" -le 0 ] || [ "$ps" -le 0 ]; then
		cat >&2 <<-EOF
		当前实例未启用 FEC（datashard=${ds}, parityshard=${ps}）。
		丢包测试依赖 KCP OOB，服务端和客户端都必须开启 FEC。
		EOF
		return 1
	fi

	local sel=""
	cat >&1 <<-'EOF'
	请选择测试时长:
	(1) 15 秒
	(2) 30 秒
	(3) 60 秒
	EOF
	read -p "(默认: 1) 请选择 [1~3]: " sel
	local duration=15
	case "$(first_character "$sel")" in
		2) duration=30 ;;
		3) duration=60 ;;
	esac

	cat >&1 <<-'EOF'
	请选择发包强度:
	(1) 低度 (100 pps, 约 0.1 Mbps)
	(2) 中度 (1000 pps, 约 1 Mbps)
	(3) 全速 (约 20000 pps, 约 20 Mbps)
	EOF
	read -p "(默认: 1) 请选择 [1~3]: " sel
	local rate="low"
	case "$(first_character "$sel")" in
		2) rate="mid" ;;
		3) rate="full" ;;
	esac

	local server_ip=""
	server_ip="$(get_server_ip)"
	if [ -z "$server_ip" ]; then
		read -p "未能自动获取服务器公网 IP, 请手动输入: " server_ip
	fi
	if [ -z "$server_ip" ]; then
		echo "未提供服务端 IP, 已取消丢包测试。"
		return 1
	fi

	local remote_cmd=""
	remote_cmd="$(losstest_build_command "$duration" "$rate" "$server_ip" './kcptun-client')"

	local total_duration=$((duration * 2))
	cat >&1 <<-EOF

	丢包测试参数: 单方向时长 ${duration} 秒, 强度 ${rate}, 总耗时约 ${total_duration} 秒
	测试原理: 上下行分开测试, 先测下行再测上行。
	          下行: 服务端发送 KCP OOB 探测包(不重传), 客户端统计收包;
	          上行: 客户端发送探测包, 服务端统计收包并回报, 回射包用于计算 RTT / 抖动。

	请将以下命令复制到客户端机器执行(需要同版本 kcptun-client):
	${remote_cmd}

	注: 全速档会产生较大流量, 请避免影响生产业务。
	EOF

	local local_bin=""
	local_bin="$(losstest_find_client 2>/dev/null || true)"
	if [ -n "$local_bin" ]; then
		read -p "是否在本机执行测试? [y/n]: " sel
		case "$(first_character "$sel")" in
			y|Y)
				local local_cmd=""
				local_cmd="$(losstest_build_command "$duration" "$rate" "$server_ip" "$local_bin")"
				echo "开始本机丢包测试..."
				sh -c "$local_cmd"
				;;
		esac
	else
		cat >&1 <<-EOF
		本机未找到 kcptun-client 二进制, 无法在本机执行测试;
		可将 client_${file_suffix} 下载/复制到 ${KCPTUN_INSTALL_DIR}/client 后重试。
		EOF
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
	local versions=""
	local version_count=0
	local list_shown="false"
	local choice=""

	while true
	do
		if [ -z "$tag_name" ]; then
			# 首次进入时拉取并展示可安装的版本列表, 失败则回退为手动输入 TAG
			if [ "$list_shown" != "true" ]; then
				echo "正在获取可用版本列表, 请稍候..."
				versions="$(list_kcptun_versions 30)"
				if [ -n "$versions" ]; then
					version_count="$(printf '%s\n' "$versions" | awk 'END { print NR }')"
					cat >&1 <<-EOF
					可用的 Kcptun 版本 (最近 ${version_count} 个, 按发布时间倒序):
					EOF
					printf '%s\n' "$versions" | awk -F '\t' '{
						date = substr($2, 1, 10)
						suffix = ($3 == "true") ? "  (预览版)" : ""
						printf "  (%2d) %-18s %s%s\n", NR, $1, date, suffix
					}'
					echo "--------------------------------------------------"
				else
					cat >&1 <<-'EOF'
					未能获取版本列表, 请手动输入完整的 TAG
					EOF
				fi
				list_shown="true"
			fi

			if [ "$version_count" -gt 0 ]; then
				read -p "(默认: 1) 请输入版本序号, 或直接输入完整 TAG: " choice
				[ -z "$choice" ] && choice="1"
			else
				read -p "(例如: v20160904): " choice
			fi

			# 纯数字且在列表范围内时按序号选择, 否则视为完整 TAG
			if [ "$version_count" -gt 0 ] && is_number "$choice" && [ ${#choice} -le 3 ]; then
				if [ "$choice" -ge 1 ] && [ "$choice" -le "$version_count" ]; then
					tag_name="$(printf '%s\n' "$versions" | sed -n "${choice}p" | cut -f1)"
				else
					echo "输入的序号超出范围, 请重新输入!"
					continue
				fi
			else
				tag_name="$choice"
			fi

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
			(7) 丢包测试
			(8) 生成客户端配置
			(9) 自定义版本安装
			(10) 删除实例
			(11) 完全卸载
			(12) 退出脚本
			EOF
			read -p "(默认: 1) 请选择 [1~12]: " sel
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
					losstest_run
					;;
				8)
					instance_clientconf
					;;
				9)
					manual_install
					;;
				10)
					select_instance
					instance_del
					;;
				11)
					do_uninstall
					;;
				12)
					;;
				*)
					echo "输入有误, 请输入有效数字 1~12!"
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
	add|reconfig|show|log|del|clientconf)
		instance_${action} "$2"
		;;
	losstest)
		losstest_run "$2"
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
