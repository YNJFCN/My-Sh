#!/bin/bash

green='\033[0;32m'
plain='\033[0m'
yellow='\033[0;33m'
red='\033[0;31m'

function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}


[[ $EUID -ne 0 ]] && echo -e "${green}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

tengine(){
    echo -e "${green}开始安装依赖软件包...${plain}"
    sudo apt install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev

    TENGINE="/main/apps/tengine"
    if [ ! -d "$TENGINE" ]; then
        sudo mkdir -p $TENGINE
    fi

    cd $TENGINE

    echo -e "${green}开始下载源码...${plain}"
    version=$(curl -Ls "https://api.github.com/repos/alibaba/tengine/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    wget -N --no-check-certificate http://tengine.taobao.org/download/tengine-${version}.tar.gz


    echo -e "${green}开始解压源码...${plain}"
    tar -zxvf tengine-${version}.tar.gz

    cd tengine-${version}

    echo -e "${green}开始配置编译选项...${plain}"
    ./configure --prefix=$TENGINE

    echo -e "${green}开始编译和安装...${plain}"
    sudo make install

    if ! grep -q "/main/apps/tengine/sbin/" /root/.bashrc; then
        echo 'export PATH="/main/apps/tengine/sbin/:$PATH"' | sudo tee -a /root/.bashrc
    fi

    sudo wget https://raw.githubusercontent.com/YNJFCN/My-Sh/main/service/nginx.service -O /etc/systemd/system/nginx.service
    sudo systemctl daemon-reload
    sudo systemctl enable nginx.service

    cd $TENGINE
    sudo rm -f tengine-${version}.tar.gz
    sudo rm -rf tengine-${version}

    source /root/.bashrc

    echo -e "${green}是否继续安装NODE.JS?${plain}"
    read -p "(y/n) 默认 n: " DONT
    if [ "$DONT" = "y" ] || [ "$DONT" = "Y" ];then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    source /root/.bashrc
    source /root/.nvm/nvm.sh
    nvm install node
    fi

    echo -e "${green}安装完成.${plain}"
    show_menu
}

Certificate(){
    echo -E ""
    LOGD "******使用说明******"
    LOGI "该脚本将使用Acme脚本申请证书,使用时需保证:"
    LOGI "1.知晓Cloudflare 注册邮箱"
    LOGI "2.知晓Cloudflare Global API Key"
    LOGI "3.域名已通过Cloudflare进行解析到当前服务器"
    LOGI "4.该脚本申请证书默认安装路径为/root/Certificate目录"
    confirm "我已确认以上内容[y/n]" "y"

    if [ $? -eq 0 ]; then
        cd ~
        LOGI "安装Acme脚本"
        curl https://get.acme.sh | sh
        source ~/.bashrc
        if [ $? -ne 0 ]; then
            LOGE "安装acme脚本失败"
            exit 1
        fi
        CF_Domain=""
        CF_GlobalKey=""
        CF_AccountEmail=""

        LOGD "是否直接颁发证书"
        read -p "[y/n]" DONT
        if [ "$DONT" = "y" ] || [ "$DONT" = "Y" ];then
        LOGD "请设置要申请的域名:"
        read -p "Input your domain here:" CF_Domain
        LOGD "你的域名设置为:${CF_Domain}"  
        release

        else
            LOGD "请设置域名:"
            read -p "Input your domain here:" CF_Domain
            LOGD "你的域名设置为:${CF_Domain}"
            LOGD "请设置API密钥:"
            read -p "Input your key here:" CF_GlobalKey
            LOGD "你的API密钥为:${CF_GlobalKey}"
            LOGD "请设置注册邮箱:"
            read -p "Input your email here:" CF_AccountEmail
            LOGD "你的注册邮箱为:${CF_AccountEmail}"
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
            if [ $? -ne 0 ]; then
                LOGE "修改默认CA为Lets'Encrypt失败,脚本退出"
                exit 1
            fi
            export CF_Key="${CF_GlobalKey}"
            export CF_Email=${CF_AccountEmail}
            release
        fi
    fi
    show_menu
}

release(){
        certPath=/root/Certificate/${CF_Domain}   
        if [ ! -d "$certPath" ]; then
            sudo mkdir -p $certPath
        fi

        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "修改默认CA为Lets'Encrypt失败,脚本退出"
            exit 1
        fi

    ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log
        if [ $? -ne 0 ]; then
            LOGE "证书签发失败,脚本退出"
            exit 1
        else
            LOGI "证书签发成功,安装中..."
        fi

    ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} --ca-file ${certPath}/ca.cer \
    --cert-file ${certPath}/${CF_Domain}.cer --key-file ${certPath}/${CF_Domain}.key \
    --fullchain-file ${certPath}/fullchain.cer
        if [ $? -ne 0 ]; then
            LOGE "证书安装失败,脚本退出"
            exit 1
        else
            LOGI "证书安装成功,开启自动更新..."
            LOGI "安装路径为${certPath}"            
        fi

    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "自动更新设置失败,脚本退出"
            ls -lah $certPath
            chmod 755 $certPath
            exit 1
        else
            LOGI "证书已安装且已开启自动更新,具体信息如下"
            ls -lah $certPath
            chmod 755 $certPath
        fi
        show_menu
}

renew(){
    echo -e "${green}开始更新软件包...${plain}"
    sudo apt update

    echo -e "${green}开始升级软件包...${plain}"
    sudo apt upgrade -y

    show_menu
}

sql(){  
    LOGI "安装MySQL"
    apt update -y
    apt install mysql-server -y
    if [ $? -ne 0 ]; then
        LOGE "Mysql安装失败,脚本退出"
        show_menu
    fi

    LOGI "启动MySQL"
    service mysql start
    if [ $? -ne 0 ]; then
        LOGE "Mysql启动失败,脚本退出"
        show_menu
    fi

    LOGI "启用开机自启动"
    sudo systemctl enable mysql
    if [ $? -ne 0 ]; then
        LOGE "自启动设置失败,脚本退出"
        show_menu
    fi

    LOGI "MySQL状态"
    sudo service mysql status

    show_menu
}

show_menu(){
    echo -e ""
    LOGD "     Ubuntu    "
    LOGD "————————————————"
    LOGI "1. ------- 安装 Tengine&NodeJS"
    LOGI "2. ------- 更新&升级 软件包"
    LOGI "3. ------- 申请SSL证书(acme申请)"
    LOGI "4. ------- 安装 Mysql"
    read -p "请输入选择 [0-∞] 任意键退出: " ORDER

    if [ "${ORDER}" = "1" ]; then
        tengine
        elif [ "${ORDER}" = "2" ]; then
        renew
        elif [ "${ORDER}" = "3" ]; then
        Certificate
        elif [ "${ORDER}" = "4" ]; then
        sql
    elif [ -z "${ORDER}"]; then
        exit 1
    fi
}

show_menu