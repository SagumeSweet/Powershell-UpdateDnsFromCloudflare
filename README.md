# 使用Powershell自动优选cloudflare并更新Windows DnsServer

## 如何使用

+ 把文件扔到cloudflareST文件夹里(github直接搜)，新建个now_IP.csv, 设置在代码最底层  
+ 计划任务用powershell加参数

    Powershell -path path

## 参考cloudflare参数

    CloudflareST.exe -url domain/200mb.test -p 0
    CloudflareST.exe -f ipv6.txt -ipv6 -url domain/200mb.test -o ipv6result.csv -p 0

## PS

我用的是旧版cloudflare测速，还有-ipv6的版本，懒得改了有空再改
