---
title: Binding a Custom Domain to GitHub Pages
date: 2021-01-13 22:27:58
tags: Domain Binding
categories: Blog Setup
lang: en
label: 018_github_pages_domain
---

-----

<!-- more -->
#### 1. Why Use a Custom Domain

I've wanted to share my tech blog with others many times, but I often couldn't even get the URL right. The structure of `donehub.github.io` is simple enough, but when you're trying to share it, it just doesn't feel polished. So to make my blog easier to remember, I needed a custom domain.

#### 2. GitHub Pages Supports Custom Domains

GitHub Pages is a solid platform for hosting blogs. After deployment, it gives you a `username.github.io` address. But GitHub Pages also provides a domain configuration option, which lets you set up a custom domain instead of using the default one. This makes binding a personal domain possible.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_46_9_github_page_domain.png)

#### 3. Binding a Custom Domain

##### 3.1 Register a Domain

Domain registrars include [Alibaba Cloud](https://wanwang.aliyun.com/?spm=5176.19720258.J_8058803260.31.69832c4a5H4h10), [GoDaddy](https://www.godaddy.com/zh-sg/domains/domain-name-search), and others. I registered mine on Alibaba Cloud: [takeshell.com](https://www.takeshell.com). It costs just a few dozen yuan per year — affordable enough.

##### 3.2 Replacing the GitHub Pages Domain

By default, GitHub Pages is deployed at `https://username.github.io/`. There are two ways to replace it with `takeshell.com`.

**Method 1:** Manually add a `CNAME` file (no extension) to your project directory with the content `takeshell.com`. After committing, you'll see the `Custom domain` field automatically populated with the new domain.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_48_22_add_cname_file.png)

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_49_32_edit_cname_file.png)

**Method 2:** Directly edit the `Custom domain` field in the settings page, enter your domain, and save.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_52_31_custom_domain.png)

##### 3.3 DNS Configuration

After switching to a custom domain, GitHub's domain health check will fail because you haven't configured DNS for your domain yet.

There are two main DNS record types for domain binding:

 * A: Stands for `Address`. DNS resolves your domain to a specific `IP` address.
 * CNAME: Stands for `Canonical Name`. DNS points your domain to another domain.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_52_59_dns_map.png)

**A Record:**

First, get the IP address by running `ping username.github.io`. For example, you might get 185.199.111.153. Then on Alibaba Cloud, go to Domain Resolution → Resolution Settings → Add Record.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_18_17_13_add_dns_a.png)

Here the host record is `www`. You'll also need to add another record with `@` as the host, so both `https://www.takeshell.com` and `https://takeshell.com` can access the blog. After enabling DNS, you can visit the blog at `takeshell.com`. The `TTL (Time To Live)` is the DNS cache duration; the default of 10 `min` is fine.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_18_17_59_add_dns_a_final.png)

**CNAME Record:**

Besides mapping directly to an IP, you can also point your domain to `username.github.io`. It's like creating a domain alias: different entry points, same destination.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_21_59_27_add_dns_cname.png)

Again, add another record with `@` as the host. After enabling DNS, you can access the blog normally at `takeshell.com`.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/03/31_22_0_0_add_dns_cname_final.png)

#### 4. Wrap-Up

Getting a custom domain is exciting. First, it should be simple enough for others to remember at a glance. Second, it should reflect your personal style: whether you're going for geek cred or everyday life, the domain should make that clear. And third, most importantly, the domain you want must actually be available.

A personal blog is a stage for showcasing your work, but if it's hidden down an alley, it's just a performance for yourself. Now that I've finally bound a custom domain, hopefully this billboard will attract more attention. The prerequisite, of course, is having something worth performing.
