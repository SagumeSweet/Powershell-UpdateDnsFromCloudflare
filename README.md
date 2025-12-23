# 使用Powershell自动优选cloudflare并更新Windows DnsServer

## 如何使用

+ 把文件扔到cloudflareST文件夹里(github直接搜)，新建个now_IP.csv
+ 脚本有两个参数，一个是cloudflareST文件夹位置，一个是测速地址
    `& .\DnsUpdate.ps1 "cfst文件夹位置" "测速地址"`
+ 计划任务用powershell加参数

    `Powershell -File "脚本位置" "cfst文件夹位置" "测速地址"`
