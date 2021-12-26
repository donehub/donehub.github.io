---
title: 用 PicGo + Gitee 搭建个人图床
date: 2021-04-23 14:57:05
tags: 图床
categories: 中间件
---

------

##### 1、拥有个人图床的必要性

图床是存储图片的服务器，可以生成外链供在线加载，被广泛用于网站建设。目前市面上主流的图床有 [`ImgURL`](https://imgurl.org/)、[`SM.MS`](https://sm.ms/)、[新浪微博](https://weibo.com/)、[路过图床](https://imgtu.com/)、[七牛云](https://www.qiniu.com/)等，主要有两个特点：免费图床广告多、不稳定；收费图床不适合打工人。作为搞技术的人，我们拥有开源精神的同时，也要利用好开源技术。[`GitHub`](https://github.com/)、[`GitLab`](https://gitlab.com/)、[`Gitee`](https://gitee.com/) 就是最干净的、最稳定的图床。由于`GitHub`、`GitLab` 在国内的访问速度远不如 `Gitee`，所以我们选择搭建 `Gitee` 图床。 

##### 2、图床工具-`PicGo`

即使有了 `Gitee` 图床，我们仍然需要借助 `Git` 将图片 `Push` 到远端，然后再到仓库中 `Copy` 在线图片的加载地址。跟那些主流图床比起来，这样做只会显得更加傻蛋。为此，我们要借助一款优秀的图床工具 `PicGo`。

> `PicGo`: 一个用于快速上传图片并获取图片 URL 链接的工具

简单地说，`PicGo` 可以主动 `Push` 图片到远端，并主动获取远端图片的外链，不用我们操心。

##### 3、搭建基于 `Gitee` 的图床

###### 3.1 创建 `Gitee` 图床仓库

创建图床仓库，需要注意两点：仓库需要开源，否则别人没有权限查看你的图片；分支只需要初始化 `master` ，图床操作都在这个分支上。

![](https://gitee.com/donehub/imgbed/raw/master/新建仓库入口.png)

![](https://gitee.com/donehub/imgbed/raw/master/PicGo下载指导.png)

###### 3.2 安装配置 `PicGo`

下载安装包：[version: 2.3.0](https://github.com/Molunerfinn/PicGo/releases/tag/v2.3.0)；

`windows`平台请选择：

![](https://gitee.com/donehub/imgbed/raw/master/新建仓库配置.png)

运行软件，可以看到【图床设置】一栏是没有 `Gitee` 的，这需要额外安装插件。操作【插件设置】，输入 `gitee` 查询相关插件，选择安装 `gitee 2.0.5`。

> 插件安装基于 `npm`，需要先安装 `Nodejs`

![](https://gitee.com/donehub/imgbed/raw/master/微信图片_20211226223238.png)

插件安装成功后重启软件，打开【图床设置】，选择【`Gitee`图床】，各项配置如下：

`owner`:  `Gitee`用户名 (`donehub`)；

`repo`: `Gitee` 图片仓库名 (`img-bed`)；

`path`: 图片存放的目录，可以不填写；

`token`: `Gitee` 上生成的私有令牌，用于授权 `PicGo` 操作 `Gitee` 图床；

`message`: 用默认证即可；

![](https://gitee.com/donehub/imgbed/raw/master/图床设置.png)

具体配置方法：

`owner` 、`repo` 容易写错，建议直接到 `Gitee` 上 `Copy`：

![](https://gitee.com/donehub/imgbed/raw/master/owner-repo.png)

`Gitee` 生成私有令牌：

步骤：个人主页-》个人设置-》安全设置-》私有令牌-》配置权限-》提交；

注意：私有令牌只会展示一次，建议复制下来长久保存；

![](https://gitee.com/donehub/imgbed/raw/master/生成私有令牌第一步.png)



![](https://gitee.com/donehub/imgbed/raw/master/生成私有令牌第二步.png)

![](https://gitee.com/donehub/imgbed/raw/master/生成私有令牌-第三步.png)

![](https://gitee.com/donehub/imgbed/raw/master/生成私有令牌第四步.png)

###### 3.3 上传图片

打开【上传区】，可以看到 `PicGo` 支持四种图片上传方式：拖拽上传、选择上传、剪切上传、`URL` 上传。返回的在线图片链接格式有 `Markdown`、`HTML` 等。

![](https://gitee.com/donehub/imgbed/raw/master/上传图片.png)

我们选择一张图片上传，上传成功后，打开【相册】。在相册里，不仅可以看到已上传的所有图片，还可以拷贝、修改在线图片链接。

![](https://gitee.com/donehub/imgbed/raw/master/相册.png)