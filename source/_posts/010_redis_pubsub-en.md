---
title: Redis Pub/Sub Explained
date: 2020-07-06 09:00:12
tags: Redis
categories: Middleware
lang: en
label: 010_redis_pubsub
---

#### 1. Background

Plenty of messaging systems implement publish-subscribe — Kafka, RabbitMQ, ActiveMQ are the big names. Lighter options include Guava's EventBus and Redis pub/sub. The MQ heavyweights get plenty of coverage elsewhere, so this post focuses on how Redis handles pub/sub under the hood. In production, Redis pub/sub sees limited adoption for two reasons. First, delivery guarantees are weak: if the network drops, in-flight messages are gone with no recovery. Second, Redis runs pub/sub through a single-threaded event loop, so a message burst can bloat the output buffer and even crash the server. That said, when data safety isn't critical, Redis pub/sub is hard to beat for simplicity.

<!-- more -->
#### 2. Basic Operations

Redis pub/sub covers four operations: subscribe, unsubscribe, pattern subscribe, and pattern unsubscribe. Here's how they work in practice:

* Start the Redis server (Windows example):

  ```cmd
  C:\Tools\Redis>redis-server.exe redis.windows.conf
  ...
  The server is now ready to accept connections on port 6379
  ```

* Create client `client1` and subscribe to channel `channel1`:

  ```cmd
  redis-cli.exe -h 127.0.0.1 -p 6379
  127.0.0.1:6379> SUBSCRIBE channel1
  Reading messages... (press Ctrl-C to quit)
  1) "subscribe"
  2) "channel1"
  3) (integer) 1
  ```

* Create client `client2` and subscribe to channel `channel2`:

  ```cmd
  redis-cli.exe -h 127.0.0.1 -p 6379
  127.0.0.1:6379> SUBSCRIBE channel2
  Reading messages... (press Ctrl-C to quit)
  1) "subscribe"
  2) "channel2"
  3) (integer) 1
  ```

* Create client `client3` and pattern-subscribe to `channel*`:

  ```cmd
  redis-cli.exe -h 127.0.0.1 -p 6379
  127.0.0.1:6379> PSUBSCRIBE channel*
  Reading messages... (press Ctrl-C to quit)
  1) "psubscribe"
  2) "channel*"
  3) (integer) 1
  ```

* Publish a message to channel `channel2`:

  ```cmd
  redis-cli.exe -h 127.0.0.1 -p 6379
  127.0.0.1:6379> PUBLISH channel2 "msg from channel2"
  (integer) 2
  127.0.0.1:6379>
  ```

* Both `client2` and `client3` receive the message:

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

Here we can see that publishers and subscribers connect through channels. Regular subscriptions use exact matching; pattern subscriptions use glob-style matching. The structure maps to this use case diagram:

![](http://www.plantuml.com/plantuml/png/SoWkIImgAStDuU8gIaqkISnBpqbLA4fDoIoEBoXDYYykJLAevk9I08ASrBGIXP9yXQBCz8mIXPHCaFBC_3omN69oINwHmjF-YKztDBzeQ4KIUx5kqSiPhK0nGso2HjW4ZI7sbHQd9YSMfog4EXig91OhA3tRiU1bu-IOlEICnBoyr9oOl8B4afBKeZmbi7A4vGgwkdOWJLPG8R0qI00iWN2F5PIDNTe8lxGnNBgMoo4rBmKOW000)

#### 3. Under the Hood

The core pub/sub implementation lives in `pubsub.c`. The relevant function declarations are visible in the `server.h` header:

```
void subscribeCommand(client *c);      /* regular subscribe */
void unsubscribeCommand(client *c);    /* regular unsubscribe */
void psubscribeCommand(client *c);     /* pattern subscribe */
void punsubscribeCommand(client *c);   /* pattern unsubscribe */
void publishCommand(client *c);
void pubsubCommand(client *c);
```

* Regular subscription flow:

```c
#define CLIENT_PUBSUB (1<<18)      /* Client is in Pub/Sub mode. */
/*-----------------------------------------------------------------------------
 * Pubsub commands implementation
 *----------------------------------------------------------------------------*/

void subscribeCommand(client *c) {
    int j;
    /* Parse client struct: c->argv[0] is the command itself, channels start at position 1 */
    for (j = 1; j < c->argc; j++)
        /* Subscribe to each channel */
        pubsubSubscribeChannel(c,c->argv[j]);
    /* Set the client to pub/sub mode; this flag is checked in processCommand */
    c->flags |= CLIENT_PUBSUB;
}

/* Subscribe a client to a channel. Returns 1 on success, 0 if already subscribed */
int pubsubSubscribeChannel(client *c, robj *channel) {
    dictEntry *de;
    list *clients = NULL;
    int retval = 0;

    /* Add the channel to the client's pubsub_channels dict; key: channel, value: NULL */
    if (dictAdd(c->pubsub_channels,channel,NULL) == DICT_OK) {
        retval = 1;
        /* Increment reference count */
        incrRefCount(channel);
        /* Look up the channel in the server's pubsub_channels dict */
        de = dictFind(server.pubsub_channels,channel);
        /* If the channel doesn't exist yet, create it */
        if (de == NULL) {
            clients = listCreate();
            /* Add the channel to the server's pubsub_channels dict; key: channel, value: client list */
            dictAdd(server.pubsub_channels,channel,clients);
             /* Increment reference count */
            incrRefCount(channel);
        } else {
            clients = dictGetVal(de);
        }
         /* Append the client to the subscriber list */
        listAddNodeTail(clients,c);
    }
    /* Notify the client of the subscription result */
    addReplyPubsubSubscribed(c,channel);
    return retval;
}
```

The regular subscription does two things: it adds the channel to the client's `pubsub_channels` dict, and it registers the client in the server's `pubsub_channels` dict. The structure looks like this:

![](http://www.plantuml.com/plantuml/png/VP5FJyCW6CRFurEGdcjJ_kpYjcRHws8yw6anXXOwYCWMIgE9-jrz1Tk5Is_yVW_mFeJz48GFuxj524bpykAYSMUDSW5_ePKNxaqQZtVuwMw3qCgTfJeEMbmKAA-wivSb_Z0oQE2Ab5WhSz8Xmijqe3vQqIeBijZsTTDfuPoov7lRamae09s00R09E01lggegIlmPxzaLzwdVuzWEO_lwlt4eve4a7_ZmV3X0c3AwaB65Z2zawooBPQ-Fl-thcoQsWjLcbYH9cacQ9CiaIv9daYUvZl87eRroykyJVm40)

![](http://www.plantuml.com/plantuml/png/RL9TJuCm57tlhsXuHa8_W4mtikZhOapKfyMOifQLYDrIG4tK_-uT26ipUBhduvnxcx1kMc7Rxhr6I5PxAuuQDyf-A8k_4ORF2lCcAujN-Eds1lMKEKYrRRGuAc2jsXsi3F5d9LiDE28XrghQwxO7BquctjQYK3NmmRACyvqMngYQ_2nBCW8AW8w00M0Zu01u7aLHuEpYtguGV_KBLi7Zy8A7hcYwulM_eGdSOuX_p5rTATCIi4mEwZlkdpSRLsPp1THry3a7Tns9xu3NUJUcSmNCBSZc78bNifYpf9ublYxZg_mq4PZExMJYKvZy01a4UY7GGM1U4vkQiei06mG-1aQU3tpY1xAfQT4BlmYjbP6d7_WF)
