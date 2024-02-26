#!/bin/bash

GREEN='\033[0;32m'
NC='\033[0m'
yellow='\033[0;33m'
NCY='\033[0m'
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}


[[ $EUID -ne 0 ]] && echo -e "${GREEN}错误：${NC} 必须使用root用户运行此脚本！\n" && exit 1

echo -e "${GREEN}开始更新软件包...${NC}"
sudo apt update

echo -e "${GREEN}开始升级软件包...${NC}"
sudo apt upgrade -y


tengine(){
    echo -e "${GREEN}开始安装依赖软件包...${NC}"
    sudo apt install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev

    TENGINE="/main/apps/tengine"
    if [ ! -d "$TENGINE" ]; then
        sudo mkdir -p $TENGINE
    fi

    cd $TENGINE

    echo -e "${GREEN}开始下载源码...${NC}"
    version=$(curl -Ls "https://api.github.com/repos/alibaba/tengine/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    wget -N --no-check-certificate http://tengine.taobao.org/download/tengine-${version}.tar.gz


    echo -e "${GREEN}开始解压源码...${NC}"
    tar -zxvf tengine-${version}.tar.gz

    cd tengine-${version}

    echo -e "${GREEN}开始配置编译选项...${NC}"
    ./configure --prefix=$TENGINE

    echo -e "${GREEN}开始编译和安装...${NC}"
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

    echo -e "${GREEN}是否继续安装NODE.JS?${NC}"
    read -p "(yes/no): " DONT
    if [ "$DONT" = "yes" ] || [ "$DONT" = "y" ];then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    source /root/.bashrc
    source /root/.nvm/nvm.sh
    nvm install node
    fi

    echo -e "${GREEN}安装完成.${NC}"
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
}

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
}

echo -e ""
LOGI "1. 安装 Tengine & NodeJS"
LOGI "2. 一键申请SSL证书(acme申请)"
LOGD "————————————————"
echo && read -p "请输入选择 [0-16]: " ORDER

if [ ${ORDER} = "1" ]; then
  tengine
  elif [ ${ORDER} = "2" ]; then
  Certificate
  else
fi