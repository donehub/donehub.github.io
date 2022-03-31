---
title: GitHub Pages 绑定个人域名
date: 2021-01-13 22:27:58
tags: 域名
categories: 运维
---

-----

#### 一、为什么要使用域名

曾经很多次想给别人介绍我熬着夜写出的技术博客，但网址是什么，我经常拼不出来。虽然 `donehub.github.io` 的结构比较简单，但摆到台面上，总差那么点意思。因此，为了让自己更容易被记住，我需要一个域名。

#### 二、`GitHub Pages` 支持域名配置

`GitHub Pages` 是一个很好的博客载体，部署成功之后会分配一个 `username.github.io` 的访问地址。同时，`GitHub Pages` 也预留了域名配置项，“我们可以定制化一个域名，不用再去访问默认的地址”。这使得绑定个人域名成为可能。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_46_9_github_page_domain.png)

#### 三、绑定个人域名

##### 3.1 申请个人域名

域名注册平台有[阿里云](https://wanwang.aliyun.com/?spm=5176.19720258.J_8058803260.31.69832c4a5H4h10)、[GoDaddy](https://www.godaddy.com/zh-sg/domains/domain-name-search) 等。我在阿里云平台注册的，叫 [takeshell.com](https://www.takeshell.com)。每年只需要几十块钱，还能玩得起。

##### 3.2 `GitHub Pages` 域名替换

`GitHub Pages` 默认是部署在 `https://username.github.io/` 上的，我们有两种方法将域名替换为 `takeshell.com`。

**方法一：**在项目目录上手动添加 `CNAME` 文件（没有后缀名），文本内容为 `takeshell.com`。提交之后，可以看到 `Custome domain` 已自动回填新的域名。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_48_22_add_cname_file.png)

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_49_32_edit_cname_file.png)

**方法二：**直接操作 `Custom domain` 配置项，填写个人域名，并保存。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_52_31_custom_domain.png)

##### 3.3 `DNS` 配置

替换为个人域名后， `GitHub` 的域名健康检测是不通过的，这是因为我们没有为个人域名配置 `DNS`。

主要有两种域名绑定方案：

 * A: 全称为`Address`，`DNS` 将个人域名解析到指定 `IP` ；
 * CNAME: 全称为 `Canonical Name`，`DNS` 将域名指向为另外一个域名；

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_52_59_dns_map.png)

**`Address` 记录类型：**

首先，通过 `ping username.github.io` 获取 `IP`，如 185.199.111.153。然后在阿里云平台，选择域名解析->解析设置->添加记录。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_18_17_13_add_dns_a.png)

这里的主机记录是 `www`，需要再添加一个 `@` 的配置，这样， `https://www.takeshell.com` 和 `https://takeshell.com` 都可以访问博客。最后启用 `DNS` ，就可以用 `takeshell.com` 访问博客了。这里的 `TTL(Time To Live)`，是 `DNS` 的缓存时间，默认10 `min` 就好了。 

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_18_17_59_add_dns_a_final.png)

**`CNAME` 记录类型：**

个人域名，除了可以直接映射到指定 `IP`  上，还可以映射到 `username.github.io` 上。相当于开启一个域名分身，虽然来路不同，但目的地是一致的。这样的映射机制也叫域名别名。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_59_27_add_dns_cname.png)

同样地，再申请一个主机记录为 `@` 的配置。开启 `DNS` 后，也可以用 `takeshell.com` 正常访问博客。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_22_0_0_add_dns_cname_final.png)

#### 四、总结

拥有个人域名是件令人兴奋的事情。首先，个人域名要足够简单，能让别人一眼记住。其次，个人域名要突出个人风格，`geek` 精神还是日常生活，通过域名必须能看出来。最后，也是最重要的，就是我们看中的域名，不能名花有主了。

个人博客是一个展示自己的舞台，但这个舞台不能深藏于巷，否则就是自导自演。如今，终于绑上了个人域名，希望这个广告牌可以吸引更多的目光。当然，前提是要有好的表演。