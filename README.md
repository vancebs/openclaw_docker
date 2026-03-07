# openclaw docker
通过Docker部署openclaw。
提供部署star-office-UI

# 部署
```bash
# first time
./start.sh -i

# non-first time start
./start.sh

# stop
./stop.sh

# find home path of openclaw
./openclaw_home_path.sh

```

# 持久化
考虑到openclaw可能会自己安装一些应用。仅持久化.openclaw在更新容器后很有可能会导致无法正常运行。所以这里将整个/home/node映射到了volume openclaw_home。可以通过脚本```openclaw_home_path.sh```获取实际路径。

