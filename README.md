# HackWithSrun

可以丢一个树莓派到需要渗透的场景下的某个角落里面

需要确保这个树莓派能够出网, 例如插一个4G卡, WIFI网卡用于连接内部网络

然后通过隧道来访问这个内部网络

## 匿名配置

要确保完全匿名, 首先需要确保主机名不泄露. 那需要首先调整NetworkManager

### NetworkManager

单独的配置, 即system-connections/*.conf:

```ini
[connection]
id=starbucks
uuid=
type=wifi
interface-name=wlan0		# 需要更改网卡

[wifi]
mode=infrastructure
ssid=starbucks				# 注意需要替换为你的需要攻击的网络的SSID
powersave=2					# 阻止网卡休眠
band=a						# a是5G,b是2.4g,可以参考文档,我只考虑使用5G

[ipv4]
method=auto					# 下面的配置是为了确保不发送hostname
dhcp-hostname=
dhcp-send-hostname=no
dhcp-fqdn=
dhcp-client-id=

[ipv6]
method=disabled				# 不需要ipv6,一般公共网络也不会提供ipv6,ipv6还有可能泄露mac地址
dhcp-send-hostname=no

[proxy]
```

conf.d/*.conf, 全局性配置(单独的配置会覆盖全局配置, 注意自己配置时不要冲突)

```ini
[device]
wifi.scan-rand-mac-address=yes		

[connection]
wifi.cloned-mac-address=random		# 每次连接都使用随机mac地址,那么每次断开再重连就会刷新ip
```

### mdns/avahi

要避免往局域网内发mdns包, 不然泄露hostname, 可能溯源

`systemctl is-active avahi-daemon`  在systemctl中查找, 如果有就关闭