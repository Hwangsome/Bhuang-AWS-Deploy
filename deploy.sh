#!/bin/bash
# AWS Elastic Beanstalk 部署脚本

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 配置变量
APP_NAME="my-nodejs-app"
ENV_NAME="my-nodejs-env"
REGION="us-west-2" # 根据您的AWS区域更改

# 检查必要的工具是否安装
check_prerequisites() {
    echo -e "${YELLOW}检查必要的工具...${NC}"
    
    # 检查AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}错误: AWS CLI未安装。请先安装AWS CLI: https://aws.amazon.com/cli/${NC}"
        exit 1
    fi
    
    # 检查AWS凭证
    aws sts get-caller-identity &> /dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: AWS凭证无效或未配置。请运行 'aws configure' 配置凭证。${NC}"
        exit 1
    fi
    
    # 检查EB CLI
    if ! command -v eb &> /dev/null; then
        echo -e "${YELLOW}EB CLI未安装。正在安装...${NC}"
        pip install awsebcli
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: 无法安装EB CLI。请手动安装: pip install awsebcli${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}所有必要工具已安装!${NC}"
}

# 初始化EB应用程序（如果未初始化）
init_eb() {
    echo -e "${YELLOW}初始化Elastic Beanstalk应用程序...${NC}"
    
    # 检查是否已初始化
    if [ ! -f ".elasticbeanstalk/config.yml" ]; then
        eb init "$APP_NAME" --region "$REGION" --platform "Node.js"
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: EB初始化失败。${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}EB应用程序已初始化。${NC}"
    fi
}

# 创建环境（如果不存在）
create_environment() {
    echo -e "${YELLOW}检查环境...${NC}"
    
    # 检查环境是否存在
    aws elasticbeanstalk describe-environments --application-name "$APP_NAME" --environment-names "$ENV_NAME" --region "$REGION" | grep "$ENV_NAME" &> /dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}环境不存在，创建新环境...${NC}"
        eb create "$ENV_NAME" --region "$REGION"
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: 无法创建环境。${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}环境已存在。${NC}"
    fi
}

# 部署应用程序
deploy_app() {
    echo -e "${YELLOW}部署应用程序到Elastic Beanstalk...${NC}"
    
    eb deploy "$ENV_NAME" --region "$REGION"
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 部署失败。${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}应用程序已成功部署!${NC}"
}

# 打开应用程序URL
open_app() {
    echo -e "${YELLOW}获取应用程序URL...${NC}"
    
    APP_URL=$(aws elasticbeanstalk describe-environments --application-name "$APP_NAME" --environment-names "$ENV_NAME" --region "$REGION" --query "Environments[0].CNAME" --output text)
    
    if [ -n "$APP_URL" ]; then
        echo -e "${GREEN}应用程序URL: http://$APP_URL${NC}"
        echo -e "${YELLOW}正在打开应用程序...${NC}"
        open "http://$APP_URL"
    else
        echo -e "${RED}错误: 无法获取应用程序URL。${NC}"
    fi
}

# 主函数
main() {
    echo -e "${GREEN}=== AWS Elastic Beanstalk Node.js部署脚本 ===${NC}"
    
    check_prerequisites
    init_eb
    create_environment
    deploy_app
    open_app
    
    echo -e "${GREEN}部署过程完成!${NC}"
}

# 执行主函数
main
