---
title: File Download with Axios
date: 2020-03-28 10:57:01
lang: en
label: 002_axios_file_download
tags: Axios
categories: Frontend
---

-----

<!-- more -->
#### 1. Background

[`Axios`](http://www.axios-js.com/zh-cn/docs/) is a [`Promise`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise)-based HTTP library that works in both the browser and Node.js. It beats traditional `Ajax` in several ways: Promise API, concurrent requests, request/response interceptors, automatic JSON handling, and XSRF protection. It also fits well with MVVM patterns, which is why it's the go-to HTTP client in `Vue`.

![](http://www.plantuml.com/plantuml/png/SoWkIImgAStDuKfCBialKdW-PSMpZkrSYUcfUIKAOPcfvKXCt_oKr1me7yBcWYYtqRK3oLizsRNaoQv9N20sK0YknKhXQN_FqmaJd--U-7JTB2wukAuTLBeejR0qjRY42yn5rbYKMboGdrUSokMGcfS2T2G0)

The problem is that Axios defaults to treating response data as JSON. When you try to download a file, you get the binary stream back, but Axios can't process it correctly. What you end up with is:

* `response.status` and `response.headers` look fine, but `response.data` is garbled
* The browser doesn't trigger a download

![](https://s1.ax1x.com/2020/03/29/GEePgI.png)

#### 2. Using Blob to Handle File Downloads

Since Axios can't handle file streams directly, we need a workaround. The [`Blob`](https://developer.mozilla.org/zh-CN/docs/Web/API/Blob) object — immutable raw data, essentially a container for binary files — does the job. Here's how to implement it:

```js
// Download file request
export function download(param) {
  return axios({
    url: '/web/bill/download',
    method: 'post',
    data: param,
    responseType: 'blob'
  })
}

// Entry point for file download
download(this.param).then(response => {
    // Execute file download
    this.exeDownloadFile(response)
})

// Execute file download
exeDownloadFile(response) {
    // Create Blob object
    let blob = new Blob([response.data], {type: response.headers['content-type']})
    // Extract filename from headers
    let fileName = response.headers['content-disposition'].match(/filename=(.*)/)[1]
    // Create a URL pointing to the Blob
    let href = window.URL.createObjectURL(blob)
    // Create an anchor element for the download
    let downloadElement = document.createElement('a')
    // Configure attributes
    downloadElement.style.display = 'none'
    downloadElement.href = href
    downloadElement.download = fileName
    // Append to current page
    document.body.appendChild(downloadElement)
    // Trigger the download
    downloadElement.click()
    // Clean up the anchor element
    document.body.removeChild(downloadElement)
    // Release the Blob URL
    window.URL.revokeObjectURL(href)
}
```

This works, but there's a catch: if the server returns an error, the `Blob` will still download a file — just with `undefined` as the filename. We need to check whether the response is actually an error before proceeding with the download:

```js
// Entry point for file download
download(this.param).then(response => {
    let fr = new FileReader()
    fr.readAsText(response.data)
    fr.onload = function() {
        // Error check: if the Blob can be parsed as JSON, it's an error response
        try {
            let jsonRet = JSON.parse(this.result)
        } catch (e) {
            // Execute file download
            this.exeDownloadFile(response)
        }
    }
})
```
