#!/bin/bash

GREEN='\033[0;32m'
NC='\033[0m'
yellow='\033[0;33m'
NCY='\033[0m'


[[ $EUID -ne 0 ]] && echo -e "${GREEN}错误：${NC} 必须使用root用户运行此脚本！\n" && exit 1

echo -e "${GREEN}开始更新软件包...${NC}"
sudo apt update

echo -e "${GREEN}开始升级软件包...${NC}"
sudo apt upgrade -y

echo -e "${GREEN}开始安装依赖软件包...${NC}"
sudo apt install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev

TENGINE="/main/apps/tengine"
if [ ! -d "$TENGINE" ]; then
    sudo mkdir -p $TENGINE
fi

cd $TENGINE

echo -e "${GREEN}开始下载源码...${NC}"
version=$(curl -Ls "https://api.github.com/repos/alibaba/tengine/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
wget http://tengine.taobao.org/download/tengine-${version}.tar.gz


echo -e "${GREEN}开始解压源码...${NC}"
tar -zxvf tengine-${version}.tar.gz

cd tengine-${version}

echo -e "${GREEN}开始配置编译选项...${NC}"
./configure --prefix=$TENGINE

echo -e "${GREEN}开始编译和安装...${NC}"
sudo make install

echo 'export PATH="/main/apps/tengine/sbin/:$PATH"' | sudo tee -a /root/.bashrc

sudo wget https://raw.githubusercontent.com/YNJFCN/My-Sh/main/service/nginx.service -O /etc/systemd/system/nginx.service
sudo systemctl daemon-reload
sudo systemctl enable nginx.service

cd $TENGINE
sudo rm -f tengine-${version}.tar.gz
sudo rm -rf tengine-${version}

source /root/.bashrc

echo -e "${yellow}是否继续安装NODE.JS?${NCY}"
read -p "(yes/no): " DONT
if [ "$DONT" = "yes" ] || [ "$DONT" = "y" ];then
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source /root/.bashrc
nvm install node
fi

echo -e "${GREEN}安装完成.${NC}"
