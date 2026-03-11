# openclaw docker
通过Docker部署openclaw。
同时部署star-office-UI

# 安装
## 下载
```bash
git clone https://github.com/vancebs/openclaw_docker.git
cd openclaw_docker
```

## 编辑配置文件
```bash
cp ./env_sample ./.env
```
复制后重点关注以下配置项：

|配置项|说明|参考设置|
|-|-|-|
|OPENCLAW_GATEWAY_ALLOWED_IP|当控制后台需要通过localhost/127.0.0.1以外的IP访问时，需要在此定义。多个IP以空格分隔|"192.168.3.50 172.16.120.20"|
|HTTP_PROXY|如果你需要代理才能访问相关网络资源那么在这里配置你的代理|"http://127.0.0.1:7890"|
|HTTPS_PROXY|如果你需要代理才能访问相关网络资源那么在这里配置你的代理|"http://127.0.0.1:7890"|
|ENABLE_CADDY|如果你需要以localhost/127.0.0.1以外的IP访问控制后台。那么只能以https访问后台。如果你没有自己的https反向代理，可以配置开启|1: 开启<br>非1: 不开启|

## 安装
```bash
./start.sh -i
```

## 控制后台配对
第一次从浏览器打开controlUI会提示```pairing required```。连接到openclaw容器 (exec.sh /bin/bash)

```bash
openclaw devices list
openclaw devices approve <requestId>
```

# 持久化
考虑到openclaw可能会自己安装一些应用。仅持久化.openclaw在更新容器后很有可能会导致无法正常运行。所以这里将整个/home/node映射到了volume openclaw_home。可以通过脚本```openclaw_home_path.sh```获取实际路径。
