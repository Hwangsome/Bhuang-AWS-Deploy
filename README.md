# AWS Elastic Beanstalk Node.js 部署示例

这是一个简单的Node.js应用程序，演示如何使用AWS Elastic Beanstalk进行部署。

## 项目结构

```
.
├── .ebextensions/         # Elastic Beanstalk配置文件
├── public/                # 静态文件目录
│   └── index.html         # 主页面
├── app.js                 # Node.js应用入口文件
├── package.json           # Node.js依赖配置
├── deploy.sh              # 部署脚本
└── README.md              # 文档
```

## 前提条件

在开始部署之前，请确保您已经：

1. 安装了 [AWS CLI](https://aws.amazon.com/cli/)
2. 通过 `aws configure` 配置了有效的AWS凭证
3. 安装了 [EB CLI](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3-install.html) (如果没有，脚本会尝试安装)
4. 有一个活跃的AWS账户，并且有权限创建Elastic Beanstalk资源

## 部署步骤

### 1. 自动部署(推荐)

使用提供的部署脚本：

```bash
./deploy.sh
```

此脚本将自动：
- 检查必要的工具是否已安装
- 初始化EB应用程序
- 创建环境(如果不存在)
- 部署应用程序
- 打开应用程序URL

### 2. 手动部署

如果您想手动部署，请按照以下步骤操作：

```bash
# 安装依赖
npm install

# 初始化EB应用程序(仅首次)
eb init my-nodejs-app --region us-west-2 --platform "Node.js"

# 创建环境(仅首次)
eb create my-nodejs-env

# 部署应用程序
eb deploy
```

## 自定义配置

如果需要修改应用配置，请编辑以下文件：

- **package.json**: 更新应用信息和依赖项
- **.ebextensions/nodecommand.config**: 修改Elastic Beanstalk配置
- **deploy.sh**: 更新部署脚本中的应用名称、环境名称和AWS区域

## 本地测试

在部署前测试应用程序：

```bash
# 安装依赖
npm install

# 启动应用
npm start
```

应用将在 [http://localhost:3000](http://localhost:3000) 启动。

## 清理资源

完成测试后，可以通过以下命令删除Elastic Beanstalk环境和应用程序：

```bash
# 终止环境
eb terminate my-nodejs-env

# 删除应用程序(需要使用AWS CLI)
aws elasticbeanstalk delete-application --application-name my-nodejs-app
```

## 注意事项

- 此应用为演示目的，在生产环境使用前请进行适当修改。
- 请记得清理不再使用的AWS资源以避免不必要的费用。


