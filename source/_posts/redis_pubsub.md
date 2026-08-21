---
title: redis 发布订阅模式
date: 2020-07-06 09:00:12
tags: Redis
categories: 中间件
---

#### 一、技术背景

实现发布订阅的中间件有许多，包括时下最热的`Kafka`、`RabbitMQ`、`ActiveMQ`，不太常见的`Guava`下的`EventBus`，以及`Redis`等。关于`MQ`之流的分析已经够多了，今天详细介绍下`Redis`的发布订阅机制及其实现。事实上，`Redis`的发布订阅机制在具体项目中的应用非常少，主要有两方面原因：其一，`Redis`的可靠性比较差，一旦出现断网等情况，则发布的消息便全部丢失；其二，`Redis`的消息处理方式是通过单线程循环遍历实现的，若存在大量的消息发布，则可能导致输出缓冲区膨胀，甚至服务崩溃。但对数据安全性和稳定性要求不高的场景来说，`Redis`不失为最佳的选择。

<!-- more -->
#### 二、基本操作

`Redis` 的发布订阅模式包括普通订阅，普通订阅取消，模式订阅，模式订阅取消这四个场景。用命令实现如下：

* 启动 `Redis` 服务（以 `Windows` 平台为例）

  ```cmd
  C:\Tools\Redis>redis-server.exe redis.windows.conf
  ...
  The server is now ready to accept connections on port 6379
  ```

* 创建客户端`client1`，并以普通订阅渠道`channel1`

  ```cmd
  redis-cli.exe -h 127.0.0.1 -p 6379
  127.0.0.1:6379> SUBSCRIBE channel1
  Reading messages... (press Ctrl-C to quit)
  1) "subscribe"
  2) "channel1"
  3) (integer) 1
  ```

* 创建客户端`client2`，并普通订阅渠道`channel2`

  ```cmd
  redis-cli.exe -h 127.0.0.1 -p 6379
  127.0.0.1:6379> SUBSCRIBE channel2
  Reading messages... (press Ctrl-C to quit)
  1) "subscribe"
  2) "channel2"
  3) (integer) 1
  ```

* 创建客户端`client3`，并模式订阅渠道`channel*`

  ```cmd
  redis-cli.exe -h 127.0.0.1 -p 6379
  127.0.0.1:6379> PSUBSCRIBE channel*
  Reading messages... (press Ctrl-C to quit)
  1) "psubscribe"
  2) "channel*"
  3) (integer) 1
  ```

* 向渠道`channel2`发布一条消息

  ```cmd
  redis-cli.exe -h 127.0.0.1 -p 6379
  127.0.0.1:6379> PUBLISH channel2 "msg from channel2"
  (integer) 2
  127.0.0.1:6379>
  ```

* `client2` 、`client3` 接收到消息

  ```cmd
  # ----------client2---------
  1) "message"
  2) "channel2"
  3) "msg from channel2"
  
  # ----------client3---------
  1) "pmessage"
  2) "channel*"
  3) "channel2"
  4) "msg from channel2"
  ```

因此，我们可以猜测，消息发布者与消息订阅者之间是通过渠道连接的，包括精准匹配（普通订阅）和模糊匹配（模式订阅）。经过分析其结构设计，可表示为用例：

![](http://www.plantuml.com/plantuml/png/SoWkIImgAStDuU8gIaqkISnBpqbLA4fDoIoEBoXDYYykJLAevk9I08ASrBGIXP9yXQBCz8mIXPHCaFBC_3omN69oINwHmjF-YKztDBzeQ4KIUx5kqSiPhK0nGso2HjW4ZI7sbHQd9YSMfog4EXig91OhA3tRiU1bu-IOlEICnBoyr9oOl8B4afBKeZmbi7A4vGgwkdOWJLPG8R0qI00iWN2F5PIDNTe8lxGnNBgMoo4rBmKOW000)

#### 三、原理分析

`Redis`发布订阅的核心实现在`pubsub.c`文件。从头文件`server.h`中可以读取相关函数声明：

```
void subscribeCommand(client *c);      /* 普通订阅 */
void unsubscribeCommand(client *c);    /* 普通订阅取消 */
void psubscribeCommand(client *c);     /* 模式订阅 */
void punsubscribeCommand(client *c);   /* 模式订阅取消 */
void publishCommand(client *c);
void pubsubCommand(client *c);
```

* 普通订阅模式：

```c
#define CLIENT_PUBSUB (1<<18)      /* Client is in Pub/Sub mode. */
/*-----------------------------------------------------------------------------
 * Pubsub commands implementation
 *----------------------------------------------------------------------------*/

void subscribeCommand(client *c) {
    int j;
	/* 分析client结构，c->argv[0]为命令本身，第2位开始为渠道参数 */
    for (j = 1; j < c->argc; j++)
        /* 订阅一个渠道 */
        pubsubSubscribeChannel(c,c->argv[j]);
    /* 设置客户端为发布订阅模式，此模式在processCommand中为校验值 */
    c->flags |= CLIENT_PUBSUB;
}

/* 一个客户端订阅一个渠道。若返回 1，则订阅成功；若返回 0，则该客户端已订阅该渠道 */
int pubsubSubscribeChannel(client *c, robj *channel) {
    dictEntry *de;
    list *clients = NULL;
    int retval = 0;

    /* 将该渠道添加到该客户端的pubsub_channels哈希表中； key: channel，value: NULL*/
    if (dictAdd(c->pubsub_channels,channel,NULL) == DICT_OK) {
        retval = 1;
        /* 引用自增 1 */
        incrRefCount(channel);
        /* 在服务端pubsub_channels中查找该channel */
        de = dictFind(server.pubsub_channels,channel);
        /* 若该channel不存在，则新建 */
        if (de == NULL) {
            clients = listCreate();
            /* 将该客户端添加到该服务端的pubsub_channels哈希表中; key: channel，value: client*/
            dictAdd(server.pubsub_channels,channel,clients);
             /* 引用自增 1 */
            incrRefCount(channel);
        } else {
            clients = dictGetVal(de);
        }
         /* 将客户端c记录在订阅客户端列表 */
        listAddNodeTail(clients,c);
    }
    /* 通知客户端订阅结果 */
    addReplyPubsubSubscribed(c,channel);
    return retval;
}
```

普通订阅模式主要做了两件事：将订阅渠道添加至客户端`pubsub_channels`哈希表中；将订阅客户端添加至服务端的`pubsub_channels`哈希表中。可如下表示：

![](http://www.plantuml.com/plantuml/png/VP5FJyCW6CRFurEGdcjJ_kpYjcRHws8yw6anXXOwYCWMIgE9-jrz1Tk5Is_yVW_mFeJz48GFuxj524bpykAYSMUDSW5_ePKNxaqQZtVuwMw3qCgTfJeEMbmKAA-wivSb_Z0oQE2Ab5WhSz8Xmijqe3vQqIeBijZsTTDfuPoov7lRamae09s00R09E01lggegIlmPxzaLzwdVuzWEO_lwlt4eve4a7_ZmV3X0c3AwaB65Z2zawooBPQ-Fl-thcoQsWjLcbYH9cacQ9CiaIv9daYUvZl87eRroykyJVm40)

![](http://www.plantuml.com/plantuml/png/RL9TJuCm57tlhsXuHa8_W4mtikZhOapKfyMOifQLYDrIG4tK_-uT26ipUBhduvnxcx1kMc7Rxhr6I5PxAuuQDyf-A8k_4ORF2lCcAujN-Eds1lMKEKYrRRGuAc2jsXsi3F5d9LiDE28XrghQwxO7BquctjQYK3NmmRACyvqMngYQ_2nBCW8AW8w00M0Zu01u7aLHuEpYtguGV_KBLi7Zy8A7hcYwulM_eGdSOuX_p5rTATCIi4mEwZlkdpSRLsPp1THry3a7Tns9xu3NUJUcSmNCBSZc78bNifYpf9ublYxZg_mq4PZExMJYKvZy01a4UY7GGM1U4vkQiei06mG-1aQU3tpY1xAfQT4BlmYjbP6d7_WF)

