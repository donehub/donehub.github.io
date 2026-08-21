---
title: 通过 Axios 实现文件下载
date: 2020-03-28 10:57:01
tags: Axios
categories: 前端
---

-----

<!-- more -->
#### 一、背景介绍

`Axios` 是一个基于 [`Promise`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise) 的 `HTTP` 库，可以用在浏览器和 `node.js` 中。与传统的 `Ajax` 相比，`Axios` 的优势主要体现在: 支持 `Promise API` 、支持并发、支持请求与响应拦截、自动转换 `JSON` 数据、支持防御 `XSRF`、符合 `MVVM` 设计理念。在目前大火的前端框架 `Vue` 中也内置了 [`Axios 框架`](<http://www.axios-js.com/zh-cn/docs/>) 。

![](http://www.plantuml.com/plantuml/png/SoWkIImgAStDuKfCBialKdW-PSMpZkrSYUcfUIKAOPcfvKXCt_oKr1me7yBcWYYtqRK3oLizsRNaoQv9N20sK0YknKhXQN_FqmaJd--U-7JTB2wukAuTLBeejR0qjRY42yn5rbYKMboGdrUSokMGcfS2T2G0)

正是因为 `Axios` 的数据处理为 `json` 格式，所以只能获取文件流，但不能给与正确处理。具体表现为:

* `response.status` 与 `repsponse.headers` 与期望相同，但 `response.data` 为一团乱码
* 浏览器没有自动下载文件 

![](https://s1.ax1x.com/2020/03/29/GEePgI.png)

#### 二、引入 `Blob`  容器实现文件下载

既然 `Axios` 无法正确处理文件流，便需要采用其他技术来达到预期效果。[`Blob`](https://developer.mozilla.org/zh-CN/docs/Web/API/Blob) 对象表示一个不可变、原始数据的类文件对象；从字面意思来看，`Blob` 也是一个可以存储二进制文件的容器。通过这项技术，可以完美地弥补 `Axios` 的不足。具体实现如下:

```js
// 下载文件请求
export function download (param) {
  return axios({
    url: '/web/bill/download',
    method: 'post',
    data: param,
    responseType: 'blob'
  })
}

// 下载文件入口方法
download(this.param).then(response => {
    // 执行文件下载
    this.exeDownloadFile(response)
})

// 执行文件下载
exeDownloadFile (response) {
    // 创建 Blob 对象
    let blob = new Blob([response.data], {type: response.headers['content-type']})
    // 获取文件名
    let fileName = response.headers['content-disposition'].match(/filename=(.*)/)[1]
    // 创建指向 Blob 对象地址的URL
    let href = window.URL.createObjectURL(blob)
    // 创建用于跳转至下载链接的 a 标签
    let downloadElement = document.createElement('a')
    // 属性配置
    downloadElement.style.display = 'none'
    downloadElement.href = href
    downloadElement.download = fileName
    // 将 a 标签挂载至当前页面
    document.body.appendChild(downloadElement)
    // 触发下载事件
    downloadElement.click()
    // 移除已挂载的 a 标签
    document.body.removeChild(downloadElement)
    // 释放 Blob URL
    window.URL.revokeObjectURL(href)
}
```

虽然以上可以实现文件下载，但美中不足的是，当后台返回异常时，通过 `Blob` 对象依然可以下载到一个 undefined 文件。因此，在执行下载之前，需要对下载请求是否存在异常做出判断。具体实现如下:

```js
// 下载文件入口方法
download(this.param).then(response => {
    let fr = new FileReader()
    fr.readAsText(response.data)
    fr.onload = function () {
        // 新增-异常校验; 若 Blob 对象可 JSON 格式化，则说明文件下载异常
    	try {
    	    let jsonRet = JSON.parse(this.result)
    	} catch (e) {
    	    // 执行文件下载
            this.exeDownloadFile(response)
    	}
    }
})
```



















