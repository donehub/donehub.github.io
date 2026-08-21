---
title: response.setHeader 与 response.addHeader 分析
date: 2020-03-22 21:28:20
tags: ServletResponse
categories: 后端
---

#### 一、背景介绍

HTTP 为请求-响应式协议，指客户端先向服务器发送请求，然后服务器接收请求后，再向客户端发送响应信息。服务器向客户端发送的响应信息，包含三个部分: 状态行、消息报头和消息正文。状态行包括 HTTP 版本和[状态码](<https://datatracker.ietf.org/doc/rfc2616/?include_text=1>)。消息报头包括浏览器、服务器或消息正文的相关信息。消息正文为返回的实体数据。

在以 Java 语言为服务的响应中，消息报头是存储在 Header 属性中的。主要实现方法有两种：`HttpServletResponse.setHeader(name, MIME)` 和 `HttpServletResponse.addHeader(name, MIME)`。下面详细介绍两种方法的底层实现原理及其区别。参考 Tomcat 源码版本8.5.31。

<!-- more -->
-----

#### 二、底层实现

![](http://www.plantuml.com/plantuml/png/tLBDgjD06DtFKym3U2-ekokHWb1Sw4PyWP0CRI2TX6Iww2uBnQ2D1eLQVxGjY9LIM-l2HbDzcdn9ynPECy4oIOJgyXOAoVUTS-PCpccvJ7LOlsSYPFC7GpDibJ9yZxYsHLtILZLL9z9AioWb6hES4bFT3Yn66bTtZHwvJRYSqpQ8gRi8AGfs2HCp33iFva-meg2pcvNpBuum96ymnrODIN3LPFYMHHcXx8mDR89XypxrvgX6uagoUI5JSkzpAYAcI_w8cOHsMFS_vUuKP2483xybyQZKaIbSe_hHBd0wdUMBeS2dupM47s7x5JwFuUqdXFdlS6DvGhaaTenEjvv1iRzwZk7PA5ikayXBeWM4GmY3xFK3SGQil-ytioiuVnHaFrVbpDlTAAZNEDMVvgy-Y5iqKWMIKBqm8buE5q-Yu1zD-cyW_Y5CrW_WLlQhNqUBOG3FXnMxryznketXyHJyBsALZoVWlsooI7N4_t97i_X5-cx2AteOgxekLRUvkHnrUdC5_98szw_vdPf_9TuaUbfhOtEySheYLP5V9TOMt_Lxvcy0)

#### 三、`setHeader` 与 `addHeader` 的区别

根据上面的分析可以看出，响应头的属性可以分为两种: 特殊属性与普通属性。其中，`Content-type` 与 `Content-length` 为特殊属性，`MimeHeaderFields`  中为普通属性。响应头的属性都在 `coyote/Response` 类中。

从底层实现原理看，`setHeader` 是通过新建或覆盖来实现属性配置的，而 `addHeader` 只会新增属性到队列中。此处需要说明，属性若已存在，`setHeader` 的进行覆盖后，还会将其他同名属性移除队列。源码实现:

``` java
// 属性组
private MimeHeaderField[] headers = new MimeHeaderField[8];

/**
 * Allow "set" operations, which removes all current values
 * for this header.
 * @param name The header name
 * @return the message bytes container for the value
 */
public MessageBytes setValue(String name) {
    for(int i = 0; i < this.count; ++i) {
        if (this.headers[i].getName().equalsIgnoreCase(name)) {
            for(int j = i + 1; j < this.count; ++j) {
                if (this.headers[j].getName().equalsIgnoreCase(name)) {
                    this.removeHeader(j--);
                }
            }
            return this.headers[i].getValue();
        }
    }
    MimeHeaderField mh = this.createHeader();
    mh.getName().setString(name);
    return mh.getValue();
}
```

继续分析，`addHeader` 为属性设置多个值，那么我们可以获取哪个值呢？通过属性名查询属性的方法有 `getHeader(name)`，`getHeaders(name)`。实现方法如下:

```java
/**
* getHeader(name)
* @param name 属性名
* @return     属性
*/
public MessageBytes getValue(String name) {
    for (int i = 0; i < count; i++) {
        if (headers[i].getName().equalsIgnoreCase(name)) {
            return headers[i].getValue();
        }
    }
    return null;
}

/**
* getHeaders(name)
* @param name 属性名
* @return     该属性名对应的所有属性值
*/
public Collection<String> getHeaders(String name) {
    Enumeration<String> enumeration =
            getCoyoteResponse().getMimeHeaders().values(name);
    List<String> result = new ArrayList<>();
    while (enumeration.hasMoreElements()) {
        result.add(enumeration.nextElement());
    }
    return result;
}
```

从方法实现可以看出，`getHeader` 会返回匹配到的第一个属性值，而 `getHeaders` 则返回相同属性名的所有属性值。我们可以通过程序示例证实：

```java
response.setHeader("set", "one");
response.setHeader("set", "two");
response.addHeader("add", "a");
response.addHeader("add", "b");
response.addHeader("add", "c");
response.addHeader("add", "d");

public static void main(String[] args) {
    
    String setName = "set";
    String addName = "add";
    
    log.info("setHeader -> getHeader 方式查询到: {}", response.getHeader(setName));
    log.info("setHeader -> getHeaders 方式查询到: {}", response.getHeaders(setName));
    
    log.info("addHeader -> getHeader 方式查询到: {}", response.getHeader(addName));
    log.info("addHeader -> getHeaders 方式查询到: {}", response.getHeaders(addName));
}

----- 输出
setHeader -> getHeader 方式查询到: two
setHeader -> getHeaders 方式查询到: two

addHeader -> getHeader 方式查询到: a
addHeader -> getHeaders 方式查询到: [a, b, c, d]
```