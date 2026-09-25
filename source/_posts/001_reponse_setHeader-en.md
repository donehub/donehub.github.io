---
title: Understanding response.setHeader vs response.addHeader
date: 2020-03-22 21:28:20
lang: en
label: 001_reponse_setHeader
tags: ServletResponse
categories: Backend
---

#### 1. Background

HTTP follows a request-response model: the client sends a request first, then the server processes it and sends back a response. That response has three parts — the status line (HTTP version and [status code](https://datatracker.ietf.org/doc/rfc2616/?include_text=1)), headers (metadata about the browser, server, or response body), and the body (the actual entity data).

In Java-based servers, response headers live in a `Header` attribute. There are two main ways to set them: `HttpServletResponse.setHeader(name, MIME)` and `HttpServletResponse.addHeader(name, MIME)`. This post digs into how they work under the hood and what the difference actually is. The Tomcat source code referenced here is version 8.5.31.

<!-- more -->
-----

#### 2. How It Works Internally

![](http://www.plantuml.com/plantuml/png/tLBDgjD06DtFKym3U2-ekokHWb1Sw4PyWP0CRI2TX6Iww2uBnQ2D1eLQVxGjY9LIM-l2HbDzcdn9ynPECy4oIOJgyXOAoVUTS-PCpccvJ7LOlsSYPFC7GpDibJ9yZxYsHLtILZLL9z9AioWb6hES4bFT3Yn66bTtZHwvJRYSqpQ8gRi8AGfs2HCp33iFva-meg2pcvNpBuum96ymnrODIN3LPFYMHHcXx8mDR89XypxrvgX6uagoUI5JSkzpAYAcI_w8cOHsMFS_vUuKP2483xybyQZKaIbSe_hHBd0wdUMBeS2dupM47s7x5JwFuUqdXFdlS6DvGhaaTenEjvv1iRzwZk7PA5ikayXBeWM4GmY3xFK3SGQil-ytioiuVnHaFrVbpDlTAAZNEDMVvgy-Y5iqKWMIKBqm8buE5q-Yu1zD-cyW_Y5CrW_WLlQhNqUBOG3FXnMxryznketXyHJyBsALZoVWlsooI7N4_t97i_X5-cx2AteOgxekLRUvkHnrUdC5_98szw_vdPf_9TuaUbfhOtEySheYLP5V9TOMt_Lxvcy0)

#### 3. The Difference Between setHeader and addHeader

Looking at the code, response headers fall into two categories: special attributes (`Content-Type` and `Content-Length`) and regular attributes (stored in `MimeHeaderFields`). All of these live in the `coyote/Response` class.

Looking at the implementation, `setHeader` creates or overwrites a value, while `addHeader` just appends to the queue. One important detail: when `setHeader` overwrites an existing attribute, it also removes all other entries with the same name from the queue. Here's the source:

```java
// Header group
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

With `addHeader`, you can set multiple values for the same attribute. The next question: which value do you actually get? There are two methods for reading headers — `getHeader(name)` and `getHeaders(name)`:

```java
/**
* getHeader(name)
* @param name Header name
* @return     Header value
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
* @param name Header name
* @return     All values for this header name
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

The implementation makes it clear: `getHeader` returns the first matching value, while `getHeaders` returns all values for that header name. We can verify this with a quick test:

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
    
    log.info("setHeader -> getHeader: {}", response.getHeader(setName));
    log.info("setHeader -> getHeaders: {}", response.getHeaders(setName));
    
    log.info("addHeader -> getHeader: {}", response.getHeader(addName));
    log.info("addHeader -> getHeaders: {}", response.getHeaders(addName));
}

----- Output
setHeader -> getHeader: two
setHeader -> getHeaders: [two]

addHeader -> getHeader: a
addHeader -> getHeaders: [a, b, c, d]
```
