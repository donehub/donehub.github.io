---
title: Building a Personal Image Host with PicGo + Gitee
date: 2021-04-23 14:57:05
tags: Image Hosting
categories: Middleware
lang: en
label: 021_build_personal_img_bed
---

------

<!-- more -->
##### 1. Why You Need a Personal Image Host

An image host is a server that stores images and generates external URLs for online loading, widely used in web development. Mainstream options include [`ImgURL`](https://imgurl.org/), [`SM.MS`](https://sm.ms/), [Sina Weibo](https://weibo.com/), [imgtu](https://imgtu.com/), and [Qiniu Cloud](https://www.qiniu.com/). These services fall into two camps: free ones are ad-heavy and unreliable, while paid ones are hard to justify for individual developers. As engineers, we should leverage open-source infrastructure to our advantage. [`GitHub`](https://github.com/), [`GitLab`](https://gitlab.com/), and [`Gitee`](https://gitee.com/) make excellent image hosts — clean, stable, and free. Since `GitHub` and `GitLab` have poor access speeds in mainland China, `Gitee` is the practical choice.

##### 2. The Image Hosting Tool — `PicGo`

Even with a `Gitee`-based image host, manually pushing images via `Git` and then copying URLs from the repo is clunky compared to using a proper image hosting service. This is where `PicGo` comes in.

> `PicGo`: A tool for quickly uploading images and retrieving their URLs.

In short, `PicGo` handles the push to remote and retrieves the external URL automatically, sparing you the manual work.

##### 3. Setting Up a `Gitee`-Based Image Host

###### 3.1 Create the `Gitee` Repository

Two things to keep in mind when creating the repo: it must be public (otherwise others can't view your images), and you only need to initialize the `master` branch — all image hosting operations happen there.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_12_34_%E6%96%B0%E5%BB%BA%E4%BB%93%E5%BA%93%E5%85%A5%E5%8F%A3.png)

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_13_20_PicGo%E4%B8%8B%E8%BD%BD%E6%8C%87%E5%AF%BC.png)

###### 3.2 Install and Configure `PicGo`

Download the installer: [version: 2.3.0](https://github.com/Molunerfinn/PicGo/releases/tag/v2.3.0);

For `Windows`, grab this:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_13_51_%E6%96%B0%E5%BB%BA%E4%BB%93%E5%BA%93%E9%85%8D%E7%BD%AE.png)

Launch the app and you'll notice the image host settings don't include `Gitee` out of the box — you need a plugin. Go to the plugin settings, search for `gitee`, and install `gitee 2.0.5`.

> Plugin installation relies on `npm`, so `Node.js` must be installed first.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_14_29_%E5%BE%AE%E4%BF%A1%E5%9B%BE%E7%89%87_20211226223238.png)

After the plugin installs, restart the app. Open the image host settings and select `Gitee`. Here's the configuration:

`owner`: Your `Gitee` username (`donehub`);

`repo`: Your `Gitee` image repository name (`img-bed`);

`path`: Directory for storing images (optional);

`token`: A private token generated on `Gitee` to authorize `PicGo` operations on your image host;

`message`: Default commit message is fine;

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_14_57_%E5%9B%BE%E5%BA%8A%E8%AE%BE%E7%BD%AE.png)

Configuration tips:

`owner` and `repo` are easy to mistype — just copy them directly from `Gitee`:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_15_41_owner-repo.png)

Generating a private token on `Gitee`:

Steps: Profile → Settings → Security → Private Token → Configure Permissions → Submit;

The token is shown only once, so save it somewhere safe.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_16_21_%E7%94%9F%E6%88%90%E7%A7%81%E6%9C%89%E4%BB%A4%E7%89%8C%E7%AC%AC%E4%B8%80%E6%AD%A5.png)

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_17_35_%E7%94%9F%E6%88%90%E7%A7%81%E6%9C%89%E4%BB%A4%E7%89%8C%E7%AC%AC%E4%BA%8C%E6%AD%A5.png)

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_18_34_%E7%94%9F%E6%88%90%E7%A7%81%E6%9C%89%E4%BB%A4%E7%89%8C-%E7%AC%AC%E4%B8%89%E6%AD%A5.png)

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_19_1_%E7%94%9F%E6%88%90%E7%A7%81%E6%9C%89%E4%BB%A4%E7%89%8C%E7%AC%AC%E5%9B%9B%E6%AD%A5.png)

###### 3.3 Upload Images

Open the upload area and you'll see `PicGo` supports four upload methods: drag-and-drop, file picker, clipboard paste, and URL upload. The returned URL comes in `Markdown`, `HTML`, and other formats.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_19_36_%E4%B8%8A%E4%BC%A0%E5%9B%BE%E7%89%87.png)

Upload an image and, once it succeeds, open the album. The album lets you view all uploaded images, copy their URLs, and edit the link format.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_20_1_%E7%9B%B8%E5%86%8C.png)

##### 4. Embedding `PicGo` into `Typora`

`PicGo` + `Gitee` works well, but manually uploading images and copying URLs is still friction. Since the image host exists to serve your writing, embedding `PicGo` directly into your editor makes sense.

`Typora` is a popular `Markdown` editor that supports embedded `PicGo` integration in version `0.9.98` and above. Once configured, dragging an image into the editor automatically uploads it to your image host and inserts the external URL.

Configuration: File → Preferences → Image → Upload image on insert → Upload settings

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_20_48_typora-picgo.png)

Open a `Test.md` file and drag an image into it. You'll see a brief loading indicator, then the image uploads and the URL gets replaced automatically.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_21_27_typora-upload-img.png)
