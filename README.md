# openclaw docker
通过Docker部署openclaw。当前已适配**2026.3.23-2**版本。

# 安装
## 下载
```bash
git clone https://github.com/vancebs/openclaw_docker.git
cd openclaw_docker
```

## 编辑配置文件
```bash
cp ./docker/local_env_sample ./local_env
```
复制后重点关注以下配置项：

|配置项|说明|参考设置|
|-|-|-|
|OPENCLAW_GATEWAY_ALLOWED_IP|当控制后台需要通过localhost/127.0.0.1以外的IP访问时，需要在此定义。多个IP以空格分隔|"192.168.3.50 172.16.120.20"|
|HTTP_PROXY|如果你需要代理才能访问相关网络资源那么在这里配置你的代理|"http://127.0.0.1:7890"|
|HTTPS_PROXY|如果你需要代理才能访问相关网络资源那么在这里配置你的代理|"http://127.0.0.1:7890"|
|NO_PROXY|开启代理的情况下同步配置这个|127.0.0.1,localhost|
|ENABLE_CADDY|通过localhost/127.0.0.1以外的IP访问控制后台，必须是https协议。如果你没有自己的https反向代理，可以配置开启caddy来自动部署https|1: 开启<br>非1: 不开启|
|CONFIG_FEISHU|onboard结束后用飞书官方插件配置飞书。注意: onboard时请跳过channel配置|1: 开启<br>非1: 不开启|
|FEISHU_APP_ID|没有bot则留空，配置时会有二维码帮你一键创建||
|FEISHU_APP_SECRET|没有bot则留空，配置时会有二维码帮你一键创建||
|ENABLE_STAR_OFFICE|部署[star-office-UI](https://github.com/ringhyacinth/Star-Office-UI)。<br>注意：openclaw接入star-office-UI需要自己导入skill|1: 开启<br>非1: 不开启|

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

# Tips
- 2026.3.8上tools权限默认为coding，如果想要获得最大权限可以修改"~/.openclaw/openclaw.json"中tools.profile的值为"full"。详见：[Tools字段说明](https://docs.openclaw.ai/zh-CN/tools#%E5%B7%A5%E5%85%B7%E9%85%8D%E7%BD%AE%E6%96%87%E4%BB%B6%EF%BC%88%E5%9F%BA%E7%A1%80%E5%85%81%E8%AE%B8%E5%88%97%E8%A1%A8%EF%BC%89)。也可以通过以下命令设置:
```bash
./exec.sh openclaw config set tools.profile 'full' --strict-json
```
  
