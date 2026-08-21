---
title: Axios 跨域下载文件解决方案
date: 2020-03-29 22:37:01
tags: Axios
categories: 前端
---

### 1. 问题描述

上篇介绍了通过`Blob` 类文件对象实现文件下载，但具体操作下去，会发现我留下了一个坑---浏览器跨域请求问题[`CORS`](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Access_control_CORS)。如下图提示:

![toVMsf.png](https://s1.ax1x.com/2020/06/10/toVMsf.png)

为实现应用解耦，前后端分离已然成为主流设计。生产环境中，前端请求需要经过代理和负载(如: `Nigix`、`LVS`)处理，才能传递到后端。此种模式下，前后端的交互实现都需要跨域。

同源安全策略是浏览器的一种安全限制，默认阻止跨域获取资源，防止跨站攻击。但 `CORS` 为跨域请求提供了可能。`CORS` 将跨域权限交给 `Web` 服务端，即通过配置就可以实现跨域地资源访问。

<!-- more -->
### 2. 跨域请求

| 跨域场景           | 示例                                         |
| ------------------ | -------------------------------------------- |
| 域名不同           | spring.io     zhihu.com                      |
| 域名相同，端口不通 | http://127.0.0.1:8080; http://127.0.0.1:8081 |
| 二级目录不同       | document.spring.io; reference.spring.io      |

综上:  当一个资源从与该资源本身所在的服务器不同的域、协议或端口请求一个资源时，资源会发起一个跨域 HTTP 请求。

### 3. 解决方案

`Access-Control-Allow-Origin` 是响应头中一个重要的属性，它规定浏览器可以获取哪些域的资源。既然 `CORS` 将跨域访问权限交给了服务器，那么只需要服务器设置 `Access-Control-Allow-Origin`属性即可。以 `Java` 为后端语言的服务中，可以做如下设置:

```java
// 为实现服务的可扩展，采用通配符域名，即允许访问所有域的资源
response.setHeader("Access-Control-Allow-Origin", "*");
```

继续实现下去，我们可能又会遇到如下问题:

![tol4mR.png](https://s1.ax1x.com/2020/06/10/tol4mR.png)

查阅资料发现，对于跨域请求，请求头的可获取性配置在属性 `Access-Control-Expose-Headers` 中，`W3C` 规定客户端获取的响应头字段仅限于`simple response header` ，包括:

- `Cache-Control`
- `Content-Language`
- `Content-Type`
- `Expires`
- `Last-Modified`
- `Pragma`

而文件名在后端的设置方式如下:

```java
response.setHeader("fileName", encodeFileName);
```

因此还后端将请求头 `fileName` 暴露给前端，配置如下:

```java
response.setHeader("fileName", encodeFileName);
response.setHeader("Access-Control-Expose-Headers", "fileName");
```

以上。










