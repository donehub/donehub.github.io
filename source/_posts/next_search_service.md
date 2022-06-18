---
title: NexT 主题集成搜索功能
date: 2020-05-03 16:28:21
tags: NexT
categories: 中间件
---

-----

#### 一、 NexT 集成第三方搜索服务

根据[官方文档](http://theme-next.iissnan.com/third-party-services.html#search-system)， NexT 主题框架集成的搜索方式有四种：

* SwiftType
* 微搜索
* Local Search
* Algolia

其中，Local Search 最为简单方便，本文将进一步介绍其配置与使用。

#### 二、配置 Local Search

* 安装插件 `hexo-generator-searchdb`：

  ```shell
  npm install hexo-generator-searchdb --save
  ```

* 编辑站点配置文件，新增以下配置：

  ```xml
  search:
    path: search.xml
    field: post
    format: html
    limit: 10000
  ```

* 编辑主题配置文件，启用本地搜索功能：

  ```xml
  # Local Search
  # Dependencies: https://github.com/theme-next/hexo-generator-searchdb
  local_search:
    enable: true
  ```

#### 三、使用 Local Search

部署博客，访问首页，可以看到新增一个搜索控件：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/06/18_20_56_47_NexT-Search-Button.png)

使用搜索功能，查看所有跟 Spring 相关的博客：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/06/18_20_58_23_NexT-Search-Demo.png)

可以看到，Local Search 不仅支持标题检索，还支持内容检索，十分好用。