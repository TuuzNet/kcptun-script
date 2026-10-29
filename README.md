# kcptun-script

Kcptun 服务端一键安装/管理脚本（2026 版）。基于 KCP 协议，将 UDP 流量通过 TCP 中转加速，显著改善高丢包、高延迟网络环境下的传输质量。

脚本完全基于 POSIX Shell 编写，交互式引导配置，支持 Debian/Ubuntu 与 CentOS/Fedora/RedHat 等 RedHat 系发行版，支持 Systemd 与 SysVinit 两种服务管理方式，并内置多实例管理能力。

## 功能特性

- **一键安装**：自动下载 Kcptun 服务端（支持 amd64 / x86 / arm64 / arm），使用 Release 的 `checksums.txt` 校验 SHA256，依赖仅需 wget/curl、gawk 与 jq
- **交互式配置**：引导式设置运行端口、加速地址、加密方式、加速模式等全部参数，均有默认值，一路回车即可完成部署
- **多实例管理**：支持添加、删除、重新配置多个 Kcptun 实例，实现多端口同时加速
- **systemd 原生托管**：自动生成 systemd unit（SysVinit 环境下生成 init 脚本），支持开机自启与崩溃自动拉起，不再依赖 Python 与 Supervisor
- **自动防火墙配置**：自动检测 firewalld / iptables 并放行 UDP 监听端口
- **一键更新**：脚本自身、配置模板、服务文件、Kcptun 主程序均可在线检查更新，并展示更新日志；`check` 命令可仅查询是否有新版本而不执行更新
- **自定义版本安装**：可指定任意 TAG 安装历史版本（不支持 v20160826 及更早版本）
- **客户端配置生成**：安装完成后自动输出服务端配置、对应的客户端 JSON 配置以及手机端参数字符串
- **下载加速**：支持 `GITHUB_PROXY` / `KCPTUN_RELEASES_API` / `KCPTUN_SCRIPT_BASE_URL` 环境变量，便于国内服务器接入镜像或反向代理
- **安全加固**：自动禁用 SELinux，默认以非 root 的 `kcptun` 用户运行服务（使用低端口或 TCP 模式时自动切换为 root）

## 目录结构

```sh
$ tree
├── kcptun.sh      # kcptun 一键安装/管理脚本
└── version.json   # 脚本自更新版本信息
```

## Kcptun 一键安装脚本

* Ubuntu：
```sh
wget --no-check-certificate -O kcptun.sh https://github.com/TuuzNet/kcptun-script/raw/main/kcptun.sh
sh kcptun.sh
```

* 其他 Linux 安装命令：
```sh
wget --no-check-certificate -O kcptun.sh https://github.com/TuuzNet/kcptun-script/raw/main/kcptun.sh
sh kcptun.sh
```

> 安装脚本需要能访问 github.com，部分国内服务器可能无法正常访问。下载失败时脚本会自动重试 3 次，仍失败可按提示手动下载文件放置到指定目录后重新运行。

### 系统要求

- **支持的系统**：Ubuntu / Debian / Raspbian / CentOS / Fedora / RedHat / OracleLinux / Photon
- **支持的架构**：x86_64（amd64）/ x86（386）/ arm64（aarch64）/ arm（armv6/armv7/armv5）
- **需要 root 权限**运行
- **服务管理**：`systemd`（优先）或 `SysVinit`（需存在 `service` 命令）
- **无需 Python**：服务由 systemd/SysVinit 直接托管

### 下载加速（可选）

安装脚本默认直连 GitHub，国内服务器可通过环境变量接入镜像：

```sh
# 为 github.com 下载地址增加加速前缀（示例）
GITHUB_PROXY='https://ghfast.top/' sh kcptun.sh

# 或直接指定 API 与脚本源
KCPTUN_RELEASES_API='https://your-mirror/api/repos/tobycroft/kcptun/releases' \
KCPTUN_SCRIPT_BASE_URL='https://your-mirror/kcptun-script/raw/main' \
sh kcptun.sh
```

### 命令行参数

* 帮助信息

```sh
# sh kcptun.sh help
请使用: kcptun.sh <option>

可使用的参数 <option> 包括:

    install          安装
    uninstall        卸载
    check            仅检查脚本与 Kcptun 是否有新版本
    update           检查并执行更新
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
```

### 版本与发布

脚本使用三个独立版本号，分别定义在 `kcptun.sh` 头部与仓库根目录的 `version.json` 中：

| 版本 | 含义 | 当前值 |
| --- | --- | --- |
| `shell_version` | 安装脚本版本 | `28` |
| `config_version` | 服务端配置文件格式版本 | `7` |
| `init_version` | 服务文件（systemd unit / init 脚本）版本 | `4` |

- `sh kcptun.sh check`：读取 `version.json` 并对比本地版本，仅输出检查结果，不修改任何文件
- `sh kcptun.sh update`：执行更新；脚本更新会先下载到临时文件，若 `version.json` 提供了 `shell_sha256` 会先校验，再替换当前脚本，下载或校验失败不会破坏现有文件

发布新版本的顺序：

1. 修改 `kcptun.sh` 中的 `SHELL_VERSION`（必要时同时修改 `CONFIG_VERSION` / `INIT_VERSION`）
2. 同步更新 `version.json` 的版本号、`change_log`、`shell_url`、`shell_sha256` 与 `release_url`
3. 提交后创建并推送 tag：`git tag -a v28 -m "kcptun-script v28" && git push origin main --tags`
4. 在 GitHub Releases 页面基于该 tag 创建 Release，粘贴 `change_log` 作为更新说明

### 交互式配置项

安装/添加实例/重新配置时会依次引导以下参数：

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| listen（端口） | 服务端监听端口，新版支持端口范围，如 `30000-35000` | `29900` |
| target（加速地址） | 需要加速的地址，支持主机名、IPv4、IPv6 | `127.0.0.1` |
| target（加速端口） | 需要加速的端口，不能与监听端口相同 | `12984` |
| key（密码） | 连接密码，两端必须一致 | `very fast` |
| crypt（加密方式） | aes / aes-128 / aes-192 / salsa20 / blowfish / twofish / cast5 / 3des / tea / xtea / xor / none | `aes` |
| mode（加速模式） | normal / fast / fast2 / fast3 / manual（手动档可配置隐藏参数） | `fast` |
| mtu | UDP 数据包最大传输单元 | `1350` |
| sndwnd | 发送窗口大小（数据包数量） | `512` |
| rcvwnd | 接收窗口大小（数据包数量） | `512` |
| datashard | 前向纠错数据分片数（通常 1~64），常规保持 10；越大吞吐越高但重组延迟与内存占用增加，两端必须一致 | `10` |
| parityshard | 前向纠错冗余分片数，0 关闭 FEC；丢包 1%~5% 建议 2~3，5%~10% 建议 4~6，超过 10% 建议 8~10，两端必须一致 | `3` |
| dscp | 差分服务代码点 | `0` |
| nocomp | 是否关闭数据压缩（文本类数据可开启，代理套壳流量建议关闭） | `true` |
| quiet | 是否屏蔽 open/close 日志输出 | `false` |
| tcp | 是否使用 TCP 传输（开启后以 root 运行） | `false` |
| snmp | 是否记录 SNMP 日志（可设置记录间隔 `snmpperiod`） | 否 |
| pprof | 是否开启 pprof 性能监控（`http://IP:6060/debug/pprof/`） | `false` |
| 隐藏参数 | acknodelay / sockbuf / smuxbuf / keepalive / smuxver / streambuf，通常保持默认即可 | 见脚本内默认值 |

选择 `manual` 加速模式时可额外配置：

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| nodelay | 是否启用 nodelay 模式 | `1`（启用） |
| interval | 协议内部工作间隔（ms） | `20` |
| resend | 快速重传模式：0 不启用 / 1 启用 / 2 跨越 2 次 ACK 直接重传 | `2` |
| nc | 是否关闭流控 | `1`（关闭流控） |

### 文件路径说明

| 路径 | 说明 |
| --- | --- |
| `/usr/local/kcptun/` | Kcptun 安装目录（含 `server_linux_amd64` 等可执行文件与 `bin/jq`） |
| `/usr/local/kcptun/server-config<id>.json` | 各实例服务端配置文件 |
| `/var/log/kcptun/server<id>.log` | 各实例运行日志 |
| `/var/log/kcptun/snmplog<id>.log` | SNMP 日志（可选） |
| `/etc/systemd/system/kcptun<id>.service` | 各实例 systemd unit（SysVinit 下为 `/etc/init.d/kcptun<id>`） |

> 若检测到旧版安装目录 `/usr/share/kcptun`，脚本会自动将文件迁移至 `/usr/local/kcptun`。

### 安装后输出

安装成功后，脚本会自动输出：

1. 服务器 IP、监听端口、加速地址及全部生效参数
2. 当前安装的 Kcptun 版本号及对应客户端下载地址
3. **客户端 JSON 配置文件**（`localaddr` 对应服务端加速端口，`remoteaddr` 对应服务器 IP + 监听端口，收发窗口自动对调）
4. **手机端参数字符串**（如 `key=very fast;crypt=aes;mode=fast;...`，可直接填入支持 Kcptun 的手机客户端）

### 重复运行脚本

已安装的情况下再次运行脚本，会进入管理菜单：

```text
(1) 覆盖安装
(2) 重新配置
(3) 添加实例(多端口)
(4) 检查更新
(5) 查看配置
(6) 查看日志输出
(7) 自定义版本安装
(8) 删除实例
(9) 完全卸载
(10) 退出脚本
```

### 常见问题

- **端口占用**：配置的监听端口若已被占用会提示重新输入
- **低端口运行**：监听端口 ≤ 1024 时，服务自动以 root 用户运行
- **旧版 Supervisor 迁移**：从 v26 及更早版本升级时，脚本会提示停止并移除 `/etc/supervisor/conf.d/kcptun*.conf`，避免同一端口重复启动
- **jq 安装失败**：优先尝试发行版软件包；仍失败时会下载 jq 1.7.1 静态二进制到 `/usr/local/kcptun/bin/jq`
- **下载失败**：可设置 `GITHUB_PROXY` 或 `KCPTUN_RELEASES_API` 使用镜像；脚本同样会自动重试 3 次
- **防火墙**：脚本会自动添加 firewalld / iptables 的 UDP 端口放行规则，失败时会输出手动添加命令
- **版本回退**：使用 `sh kcptun.sh manual` 输入完整 TAG（如 `v20160904`）即可安装指定历史版本
