---
title: Integrating Search into the NexT Theme
date: 2020-05-03 16:28:21
tags: NexT
categories: Middleware
lang: en
label: 007_next_search_service
---

-----

<!-- more -->
#### 1. NexT's Third-Party Search Integrations

According to the [official documentation](http://theme-next.iissnan.com/third-party-services.html#search-system), the NexT theme framework supports four search methods:

* SwiftType
* Micro Search
* Local Search
* Algolia

Local Search is the simplest and most convenient option. Here's how to set it up.

#### 2. Configuring Local Search

* Install the `hexo-generator-searchdb` plugin:

  ```shell
  npm install hexo-generator-searchdb --save
  ```

* Add the following configuration to your site config file:

  ```xml
  search:
    path: search.xml
    field: post
    format: html
    limit: 10000
  ```

* Enable local search in your theme config file:

  ```xml
  # Local Search
  # Dependencies: https://github.com/theme-next/hexo-generator-searchdb
  local_search:
    enable: true
  ```

#### 3. Using Local Search

After deploying the blog, head to the homepage — you'll see a search button:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/06/18_20_56_47_NexT-Search-Button.png)

Use the search feature to find all Spring-related posts:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/06/18_20_58_23_NexT-Search-Demo.png)

Local Search supports both title and full-text search, making it genuinely useful out of the box.
