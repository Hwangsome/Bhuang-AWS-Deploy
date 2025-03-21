#!/bin/bash
# AWS Elastic Beanstalk 资源创建脚本
# 基于 AWS CLI文档：https://docs.aws.amazon.com/cli/latest/reference/elasticbeanstalk/

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量 - 请根据需要修改
APP_NAME="my-nodejs-app"
ENV_NAME="my-nodejs-env"
REGION="us-east-1"  # 改为与您当前区域一致
INSTANCE_TYPE="t2.micro"
# 使用正确的平台标识符，将在脚本中设置
SERVICE_ROLE_NAME="aws-elasticbeanstalk-service-role"
EC2_ROLE_NAME="aws-elasticbeanstalk-ec2-role"
S3_BUCKET="${APP_NAME}-elasticbeanstalk-deployment-$(date +%s)"

# 打印标题
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# 检查必要的工具是否安装
check_prerequisites() {
    print_header "检查必要的工具"
    
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
    
    # 检查JQ（用于解析JSON响应）
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}jq未安装。正在安装...${NC}"
        if [ "$(uname)" == "Darwin" ]; then
            # macOS
            brew install jq
        elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
            # Linux
            sudo apt-get update && sudo apt-get install -y jq
        else
            echo -e "${RED}错误: 无法自动安装jq。请手动安装。${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}所有必要工具已安装!${NC}"
}

# 获取可用的平台列表并选择Node.js平台
select_platform() {
    print_header "选择Node.js平台"
    
    # 直接使用固定平台名称，这是基于官方支持的平台格式
    # 选择 Node.js 22 on Amazon Linux 2023
    PLATFORM="64bit Amazon Linux 2023 v6.4.3 running Node.js 22"
    
    # 可选的备用平台
    NODE_18_PLATFORM="64bit Amazon Linux 2023 v6.4.3 running Node.js 18"
    NODE_20_PLATFORM="64bit Amazon Linux 2023 v6.4.3 running Node.js 20"
    
    echo -e "${GREEN}选择平台: ${PLATFORM}${NC}"
    echo -e "${YELLOW}可用的备选平台:${NC}"
    echo -e "1. ${NODE_18_PLATFORM}"
    echo -e "2. ${NODE_20_PLATFORM}"
}

# 创建IAM角色和策略
create_iam_roles() {
    print_header "创建IAM角色和策略"
    
    # 检查服务角色是否存在
    if aws iam get-role --role-name "$SERVICE_ROLE_NAME" &> /dev/null; then
        echo -e "${GREEN}服务角色 $SERVICE_ROLE_NAME 已存在${NC}"
    else
        echo -e "${YELLOW}创建服务角色 $SERVICE_ROLE_NAME...${NC}"
        
        # 创建服务角色
        aws iam create-role \
            --role-name "$SERVICE_ROLE_NAME" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "elasticbeanstalk.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }'
            
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: 无法创建服务角色。${NC}"
            exit 1
        fi
            
        # 附加策略
        aws iam attach-role-policy \
            --role-name "$SERVICE_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService"
            
        aws iam attach-role-policy \
            --role-name "$SERVICE_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
            
        # 等待角色传播
        echo -e "${YELLOW}等待IAM角色传播...${NC}"
        sleep 10
            
        echo -e "${GREEN}服务角色创建完成${NC}"
    fi
    
    # 检查EC2实例角色是否存在
    if aws iam get-role --role-name "$EC2_ROLE_NAME" &> /dev/null; then
        echo -e "${GREEN}EC2实例角色 $EC2_ROLE_NAME 已存在${NC}"
    else
        echo -e "${YELLOW}创建EC2实例角色 $EC2_ROLE_NAME...${NC}"
        
        # 创建EC2实例角色
        aws iam create-role \
            --role-name "$EC2_ROLE_NAME" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "ec2.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }'
            
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: 无法创建EC2实例角色。${NC}"
            exit 1
        fi
            
        # 附加策略
        aws iam attach-role-policy \
            --role-name "$EC2_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
            
        aws iam attach-role-policy \
            --role-name "$EC2_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
            
        # 创建实例配置文件
        aws iam create-instance-profile --instance-profile-name "$EC2_ROLE_NAME"
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: 无法创建实例配置文件。${NC}"
            exit 1
        fi
        
        # 将角色添加到实例配置文件
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$EC2_ROLE_NAME" \
            --role-name "$EC2_ROLE_NAME"
            
        # 等待角色传播
        echo -e "${YELLOW}等待IAM角色传播...${NC}"
        sleep 10
            
        echo -e "${GREEN}EC2实例角色创建完成${NC}"
    fi
}

# 创建S3存储桶
create_s3_bucket() {
    print_header "创建S3存储桶"
    
    # 检查存储桶是否存在
    if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        echo -e "${GREEN}S3存储桶 $S3_BUCKET 已存在${NC}"
    else
        echo -e "${YELLOW}创建S3存储桶 $S3_BUCKET...${NC}"
        
        # 创建存储桶
        if [ "$REGION" == "us-east-1" ]; then
            aws s3api create-bucket \
                --bucket "$S3_BUCKET" \
                --region "$REGION"
        else
            aws s3api create-bucket \
                --bucket "$S3_BUCKET" \
                --region "$REGION" \
                --create-bucket-configuration LocationConstraint="$REGION"
        fi
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: 无法创建S3存储桶。请确保存储桶名称全局唯一并且您有创建权限。${NC}"
            # 修改存储桶名称并重试
            S3_BUCKET="${APP_NAME}-eb-$(date +%s)-$(openssl rand -hex 4)"
            echo -e "${YELLOW}尝试使用新名称: $S3_BUCKET${NC}"
            
            if [ "$REGION" == "us-east-1" ]; then
                aws s3api create-bucket \
                    --bucket "$S3_BUCKET" \
                    --region "$REGION"
            else
                aws s3api create-bucket \
                    --bucket "$S3_BUCKET" \
                    --region "$REGION" \
                    --create-bucket-configuration LocationConstraint="$REGION"
            fi
            
            if [ $? -ne 0 ]; then
                echo -e "${RED}仍然无法创建S3存储桶。请手动创建并更新脚本中的S3_BUCKET变量。${NC}"
                exit 1
            fi
        fi
        
        # 启用版本控制
        aws s3api put-bucket-versioning \
            --bucket "$S3_BUCKET" \
            --versioning-configuration Status=Enabled \
            --region "$REGION"
            
        echo -e "${GREEN}S3存储桶创建完成: $S3_BUCKET${NC}"
    fi
}

# 创建Elastic Beanstalk应用程序
create_eb_application() {
    print_header "创建Elastic Beanstalk应用程序"
    
    # 检查应用程序是否存在
    if aws elasticbeanstalk describe-applications --application-names "$APP_NAME" --region "$REGION" 2>/dev/null | grep -q "$APP_NAME"; then
        echo -e "${GREEN}应用程序 $APP_NAME 已存在${NC}"
    else
        echo -e "${YELLOW}创建应用程序 $APP_NAME...${NC}"
        
        # 创建应用程序
        aws elasticbeanstalk create-application \
            --application-name "$APP_NAME" \
            --description "Node.js application deployed with Elastic Beanstalk" \
            --region "$REGION"
            
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: 无法创建应用程序。${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}应用程序创建完成${NC}"
    fi
}

# 创建安全组
create_security_group() {
    print_header "创建安全组"
    
    # 检查安全组是否存在
    SG_NAME="${APP_NAME}-sg"
    SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SG_NAME" --region "$REGION" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
    
    if [[ "$SG_ID" != "None" && "$SG_ID" != "" ]]; then
        echo -e "${GREEN}安全组 $SG_NAME 已存在 (ID: $SG_ID)${NC}"
    else
        echo -e "${YELLOW}创建安全组 $SG_NAME...${NC}"
        
        # 获取默认VPC ID
        VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --region "$REGION" --query 'Vpcs[0].VpcId' --output text)
        
        if [[ "$VPC_ID" == "None" || "$VPC_ID" == "" ]]; then
            echo -e "${RED}错误: 无法获取默认VPC ID。${NC}"
            # 尝试获取任何VPC
            VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --query 'Vpcs[0].VpcId' --output text)
            
            if [[ "$VPC_ID" == "None" || "$VPC_ID" == "" ]]; then
                echo -e "${RED}错误: 在区域 $REGION 中没有可用的VPC。请先创建VPC。${NC}"
                exit 1
            else
                echo -e "${YELLOW}使用默认非默认VPC: $VPC_ID${NC}"
            fi
        fi
        
        # 创建安全组
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SG_NAME" \
            --description "Security group for $APP_NAME Elastic Beanstalk environment" \
            --vpc-id "$VPC_ID" \
            --region "$REGION" \
            --query 'GroupId' --output text)
            
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: 无法创建安全组。${NC}"
            exit 1
        fi
            
        # 添加入站规则
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0 \
            --region "$REGION"
            
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 443 \
            --cidr 0.0.0.0/0 \
            --region "$REGION"
            
        # 添加SSH访问（可选）
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0 \
            --region "$REGION"
            
        echo -e "${GREEN}安全组创建完成 (ID: $SG_ID)${NC}"
    fi
}

# 创建Elastic Beanstalk配置模板
create_eb_configuration() {
    print_header "创建Elastic Beanstalk配置模板"
    
    CONFIG_NAME="${APP_NAME}-config"
    
    # 检查配置模板是否存在
    if aws elasticbeanstalk describe-configuration-settings \
        --application-name "$APP_NAME" \
        --template-name "$CONFIG_NAME" --region "$REGION" &>/dev/null; then
        echo -e "${GREEN}配置模板 $CONFIG_NAME 已存在${NC}"
    else
        echo -e "${YELLOW}创建配置模板 $CONFIG_NAME...${NC}"
        
        # 检查选择的平台是否有效
        echo "DEBUG: 使用平台: '$PLATFORM'"
        
        # 创建配置模板
        if ! aws elasticbeanstalk create-configuration-template \
            --application-name "$APP_NAME" \
            --template-name "$CONFIG_NAME" \
            --solution-stack-name "$PLATFORM" \
            --option-settings file://eb-config-options.json \
            --region "$REGION"; then
            
            echo -e "${RED}错误: 无法创建配置模板。请确保平台名称有效。${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}配置模板创建完成${NC}"
    fi
}

# 创建Elastic Beanstalk环境
create_eb_environment() {
    print_header "创建Elastic Beanstalk环境"
    
    # 检查环境是否存在
    if aws elasticbeanstalk describe-environments \
        --application-name "$APP_NAME" \
        --environment-names "$ENV_NAME" \
        --region "$REGION" \
        --query "Environments[?Status!='Terminated']" \
        --output text | grep -q "$ENV_NAME"; then
        echo -e "${GREEN}环境 $ENV_NAME 已存在${NC}"
        
        # 获取环境状态
        ENV_STATUS=$(aws elasticbeanstalk describe-environments \
            --application-name "$APP_NAME" \
            --environment-names "$ENV_NAME" \
            --region "$REGION" \
            --query "Environments[0].Status" \
            --output text)
            
        echo -e "${YELLOW}环境状态: $ENV_STATUS${NC}"
    else
        echo -e "${YELLOW}创建环境 $ENV_NAME...${NC}"
        
        # 检查选择的平台是否有效
        echo "DEBUG: 使用平台: '$PLATFORM'"
        
        # 创建环境
        if ! aws elasticbeanstalk create-environment \
            --application-name "$APP_NAME" \
            --environment-name "$ENV_NAME" \
            --solution-stack-name "$PLATFORM" \
            --option-settings file://eb-config-options.json \
            --region "$REGION"; then
            
            echo -e "${RED}错误: 无法创建环境。请确保平台名称有效。${NC}"
            exit 1
        fi
            
        # 等待环境创建完成
        echo -e "${YELLOW}等待环境创建完成(这可能需要几分钟)...${NC}"

        # 等待环境变为就绪状态
        RETRIES=0
        MAX_RETRIES=30  # 最多等待30次检查，大约分钟
        
        while [ $RETRIES -lt $MAX_RETRIES ]; do
            ENV_STATUS=$(aws elasticbeanstalk describe-environments \
                --application-name "$APP_NAME" \
                --environment-names "$ENV_NAME" \
                --region "$REGION" \
                --query "Environments[0].Status" \
                --output text)
                
            echo -e "${YELLOW}当前状态: $ENV_STATUS${NC}"
            
            if [ "$ENV_STATUS" == "Ready" ]; then
                break
            fi
            
            RETRIES=$((RETRIES+1))
            echo -e "${YELLOW}等待中... ($RETRIES/$MAX_RETRIES)${NC}"
            sleep 10
        done
        
        if [ "$ENV_STATUS" != "Ready" ]; then
            echo -e "${YELLOW}环境仍在创建中，但脚本将继续。您可以后续检查状态。${NC}"
        else
            echo -e "${GREEN}环境创建完成并就绪!${NC}"
        fi
        
        # 获取环境URL
        ENV_URL=$(aws elasticbeanstalk describe-environments \
            --application-name "$APP_NAME" \
            --environment-names "$ENV_NAME" \
            --region "$REGION" \
            --query "Environments[0].CNAME" \
            --output text)
            
        if [ -n "$ENV_URL" ]; then
            echo -e "${GREEN}环境URL: http://$ENV_URL${NC}"
        fi
    fi
}

# 创建配置文件
create_config_file() {
    print_header "创建配置选项文件"
    
    # 创建简化的配置选项文件，移除NodeVersion设置
    cat << EOF > eb-config-options.json
[
    {
        "Namespace": "aws:autoscaling:launchconfiguration",
        "OptionName": "IamInstanceProfile",
        "Value": "${EC2_ROLE_NAME}"
    },
    {
        "Namespace": "aws:autoscaling:launchconfiguration",
        "OptionName": "InstanceType",
        "Value": "${INSTANCE_TYPE}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:environment",
        "OptionName": "ServiceRole",
        "Value": "${SERVICE_ROLE_NAME}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:environment",
        "OptionName": "EnvironmentType",
        "Value": "SingleInstance"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "NODE_ENV",
        "Value": "production"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application",
        "OptionName": "Application Healthcheck URL",
        "Value": "/"
    }
]
EOF

    echo -e "${GREEN}配置选项文件已创建: eb-config-options.json${NC}"
}

# 主函数
main() {
    print_header "AWS Elastic Beanstalk 资源创建脚本"
    
    check_prerequisites
    select_platform  # 添加平台选择步骤
    create_iam_roles
    create_s3_bucket
    create_eb_application
    create_config_file
    
    # 跳过创建配置模板和安全组，直接创建环境
    create_eb_environment
    
    print_header "资源创建完成"
    echo -e "${GREEN}所有AWS Elastic Beanstalk资源已创建完成!${NC}"
    echo -e "${YELLOW}应用程序名称: ${NC}${APP_NAME}"
    echo -e "${YELLOW}环境名称: ${NC}${ENV_NAME}"
    echo -e "${YELLOW}区域: ${NC}${REGION}"
    echo -e "${YELLOW}平台: ${NC}${PLATFORM}"
    echo -e "${YELLOW}S3存储桶: ${NC}${S3_BUCKET}"
    
    # 获取环境URL
    ENV_URL=$(aws elasticbeanstalk describe-environments \
        --application-name "$APP_NAME" \
        --environment-names "$ENV_NAME" \
        --region "$REGION" \
        --query "Environments[0].CNAME" \
        --output text)
        
    if [ -n "$ENV_URL" ]; then
        echo -e "${YELLOW}环境URL: ${NC}http://$ENV_URL"
        echo -e "\n${GREEN}现在可以使用 deploy.sh 脚本部署应用程序了${NC}"
    fi
    
    echo -e "\n${YELLOW}提示: ${NC}环境创建可能需要几分钟才能完成。您可以使用以下命令检查状态:"
    echo -e "aws elasticbeanstalk describe-environments --application-name \"$APP_NAME\" --environment-names \"$ENV_NAME\" --region \"$REGION\" --query \"Environments[0].Status\" --output text"
}

# 执行主函数
main