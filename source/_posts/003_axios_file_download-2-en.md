---
title: Cross-Origin File Download with Axios
date: 2020-03-29 22:37:01
lang: en
label: 003_axios_file_download-2
tags: Axios
categories: Frontend
---

### 1. The Problem

The previous post covered file downloads using the `Blob` object, but there's a problem I glossed over: cross-origin requests. When the frontend and backend run on different domains, the browser's [`CORS`](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Access_control_CORS) policy kicks in and blocks the download. Here's what the console looks like:

![toVMsf.png](https://s1.ax1x.com/2020/06/10/toVMsf.png)

In a typical setup where the frontend and backend are deployed separately, production requests go through proxies and load balancers (like `Nginx` or `LVS`) before reaching the backend. That means the frontend and backend almost always sit on different origins, and every request needs to handle cross-origin properly.

Same-origin policy is a browser security mechanism that blocks cross-origin resource access by default. It exists to prevent cross-site attacks. `CORS` shifts the decision to the server — the server tells the browser which origins are allowed through response headers.

<!-- more -->
### 2. When Does Cross-Origin Happen?

| Scenario | Example |
| --- | --- |
| Different domain | spring.io vs zhihu.com |
| Same domain, different port | http://127.0.0.1:8080 vs http://127.0.0.1:8081 |
| Different subdomain | document.spring.io vs reference.spring.io |

In short, any time a resource is requested from a different domain, protocol, or port than where the resource itself lives, it's a cross-origin request.

### 3. The Solution

`Access-Control-Allow-Origin` is the key response header. It tells the browser which domains are permitted to access the resource. Since CORS puts the control in the server's hands, all we need to do is set this header on the backend:

```java
// Using a wildcard to allow all origins — useful for scaling across multiple domains
response.setHeader("Access-Control-Allow-Origin", "*");
```

But if you stop there, you might hit another issue:

![tol4mR.png](https://s1.ax1x.com/2020/06/10/tol4mR.png)

The file downloaded, but the filename is missing. The reason is that for cross-origin requests, the browser only exposes a limited set of response headers to client-side JavaScript — the so-called "simple response headers":

- `Cache-Control`
- `Content-Language`
- `Content-Type`
- `Expires`
- `Last-Modified`
- `Pragma`

If the backend sets a custom header like `fileName` to pass the filename, the frontend can't read it unless the server explicitly exposes it. The backend sets the filename like this:

```java
response.setHeader("fileName", encodeFileName);
```

To make it accessible on the frontend, the server also needs to add the `Access-Control-Expose-Headers` header:

```java
response.setHeader("fileName", encodeFileName);
response.setHeader("Access-Control-Expose-Headers", "fileName");
```

That's it — the browser will now let JavaScript read the `fileName` header, and the download works correctly across origins.
