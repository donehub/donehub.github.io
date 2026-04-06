---
title: 用 Hexo + GitHub Pages 搭建个人博客
date: 2020-03-20
tags: Hexo
categories: 博客搭建
---

------

##### 1、为什么要搭建个人博客

在互联网时代，拥有一个个人博客有很多好处：

- **知识沉淀**：将学习笔记、技术总结整理成文章，方便日后查阅
- **个人品牌**：展示技术能力，吸引潜在雇主或合作伙伴
- **完全自主**：相比第三方平台，个人博客完全由自己掌控
- **成本低廉**：GitHub Pages 免费提供静态网站托管服务

主流的博客搭建方案有 [`Hexo`](https://hexo.io/)、[`Hugo`](https://gohugo.io/)、[`Jekyll`](https://jekyllrb.com/)、[`WordPress`](https://wordpress.org/) 等。其中 `Hexo` 基于 `Node.js`，具有以下优点：

- 生成静态页面，访问速度快
- 主题丰富，可定制性强
- 支持 Markdown 写作
- 一键部署到 GitHub Pages

本文将手把手教你搭建一个基于 `Hexo` + `GitHub Pages` 的个人博客。

##### 2、环境准备

###### 2.1 安装 Node.js

`Hexo` 基于 `Node.js` 运行，需要先安装 `Node.js`。

**Windows 系统：**

1. 访问 [Node.js 官网](https://nodejs.org/)
2. 下载 LTS（长期支持版）安装包，推荐 `18.x` 或 `20.x` 版本
3. 双击安装包，一路点击 "Next" 完成安装

**验证安装：**

打开命令行（按 `Win + R`，输入 `cmd`，回车），执行以下命令：

```bash
node -v
npm -v
```

如果显示版本号，说明安装成功：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2026/04/node_version.png)

###### 2.2 安装 Git

`Git` 是版本控制工具，用于将博客部署到 `GitHub`。

**Windows 系统：**

1. 访问 [Git 官网](https://git-scm.com/download/win)
2. 下载 Windows 安装包
3. 双击安装包，默认选项安装即可

**验证安装：**

打开命令行，执行：

```bash
git --version
```

显示版本号则安装成功。

###### 2.3 注册 GitHub 账号

如果还没有 `GitHub` 账号，请前往 [GitHub 官网](https://github.com/) 注册。注册完成后，建议配置 SSH 密钥，方便后续部署。

**生成 SSH 密钥：**

```bash
# 配置 Git 用户信息
git config --global user.name "你的用户名"
git config --global user.email "你的邮箱"

# 生成 SSH 密钥
ssh-keygen -t rsa -C "你的邮箱"
```

连续按三次回车，使用默认配置。密钥会生成在 `C:\Users\你的用户名\.ssh` 目录下。

**添加 SSH 密钥到 GitHub：**

1. 用记事本打开 `.ssh` 目录下的 `id_rsa.pub` 文件，复制全部内容
2. 登录 GitHub，点击右上角头像 → Settings → SSH and GPG keys → New SSH key
3. 粘贴密钥内容，点击 "Add SSH key"

**验证 SSH 连接：**

```bash
ssh -T git@github.com
```

如果显示 `Hi xxx! You've successfully authenticated...`，说明配置成功。

##### 3、安装 Hexo

###### 3.1 创建博客目录

选择一个合适的位置存放博客文件，比如 `D:\Blog`。在命令行中执行：

```bash
# 切换到 D 盘
D:

# 创建博客目录
mkdir myblog

# 进入目录
cd myblog
```

###### 3.2 安装 Hexo 脚手架

```bash
npm install -g hexo-cli
```

安装完成后，验证：

```bash
hexo -v
```

###### 3.3 初始化博客

```bash
# 初始化博客，blog 是博客文件夹名称
hexo init blog

# 进入博客目录
cd blog

# 安装依赖
npm install
```

初始化完成后，目录结构如下：

```
blog
├── _config.yml      # 站点配置文件
├── package.json     # 依赖配置
├── scaffolds        # 文章模板
├── source           # 资源文件
│   ├── _drafts      # 草稿
│   └── _posts       # 已发布的文章
└── themes           # 主题文件夹
```

###### 3.4 本地预览博客

```bash
# 启动本地服务器
hexo server

# 或者简写
hexo s
```

打开浏览器访问 `http://localhost:4000`，即可看到博客初始页面。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2026/04/hexo_init_page.png)

按 `Ctrl + C` 停止服务器。

##### 4、GitHub Pages 配置

###### 4.1 创建仓库

1. 登录 GitHub，点击右上角 "+" → "New repository"
2. 仓库名称必须是 `你的用户名.github.io`（例如：`donehub.github.io`）
3. 选择 "Public"（公开）
4. 点击 "Create repository"

> 注意：仓库名称必须是 `用户名.github.io` 格式，这是 GitHub Pages 的要求。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2026/04/github_create_repo.png)

###### 4.2 配置部署信息

编辑博客根目录下的 `_config.yml` 文件，找到 `deploy` 部分，修改为：

```yaml
# Deployment
deploy:
  type: git
  repo: git@github.com:你的用户名/你的用户名.github.io.git
  branch: master
```

例如：

```yaml
deploy:
  type: git
  repo: git@github.com:donehub/donehub.github.io.git
  branch: master
```

###### 4.3 安装部署插件

```bash
npm install hexo-deployer-git --save
```

##### 5、配置博客

###### 5.1 修改站点信息

打开 `_config.yml`，修改以下配置：

```yaml
# Site
title: 我的博客              # 博客标题
subtitle: '记录学习和生活'    # 博客副标题
description: ''             # 博客描述
keywords:                   # 关键词
author: 你的名字             # 作者名称
language: zh-CN             # 语言，中文
timezone: 'Asia/Shanghai'   # 时区

# URL
url: https://你的用户名.github.io  # 博客地址
root: /
permalink: :year/:month/:day/:title/  # 文章链接格式
```

###### 5.2 常用命令

| 命令 | 简写 | 说明 |
|------|------|------|
| `hexo new "文章标题"` | `hexo n "文章标题"` | 新建文章 |
| `hexo generate` | `hexo g` | 生成静态文件 |
| `hexo server` | `hexo s` | 启动本地服务器 |
| `hexo deploy` | `hexo d` | 部署到远程仓库 |
| `hexo clean` | - | 清除缓存文件 |

常用组合：

```bash
# 清除缓存 + 生成 + 部署
hexo clean && hexo g && hexo d
```

##### 6、更换主题

Hexo 默认主题比较简单，推荐安装 [`NexT`](https://github.com/next-theme/hexo-theme-next) 主题，简洁美观，功能强大。

###### 6.1 安装 NexT 主题

```bash
# 进入博客根目录，安装 NexT 主题
npm install hexo-theme-next --save
```

或者使用 Git 克隆：

```bash
cd blog
git clone https://github.com/next-theme/hexo-theme-next.git themes/next
```

###### 6.2 启用主题

修改 `_config.yml` 中的主题配置：

```yaml
theme: next
```

###### 6.3 主题配置

NexT 主题有独立的配置文件 `_config.next.yml`（推荐）或 `themes/next/_config.yml`。

创建 `_config.next.yml` 进行个性化配置：

```yaml
# 选择主题风格
scheme: Muse          # 默认风格，黑白分明
# scheme: Mist        # 类似 Muse，更简洁
# scheme: Pisces      # 双栏布局
# scheme: Gemini      # 类似 Pisces，更精致

# 菜单配置
menu:
  home: / || fa fa-home
  archives: /archives/ || fa fa-archive
  tags: /tags/ || fa fa-tags
  categories: /categories/ || fa fa-th
  about: /about/ || fa fa-user

# 侧边栏社交链接
social:
  GitHub: https://github.com/你的用户名 || fab fa-github

# 头像
avatar:
  url: /images/avatar.png    # 头像图片路径
  rounded: true              # 圆形头像
  opacity: 1

# 代码高亮主题
codeblock:
  theme:
    light: default
    dark: stackoverflow-dark
```

###### 6.4 创建分类和标签页面

```bash
# 创建分类页面
hexo new page categories

# 创建标签页面
hexo new page tags

# 创建关于页面
hexo new page about
```

编辑 `source/categories/index.md`：

```markdown
---
title: 分类
date: 2026-04-06 15:00:00
type: "categories"
---
```

编辑 `source/tags/index.md`：

```markdown
---
title: 标签
date: 2026-04-06 15:00:00
type: "tags"
---
```

##### 7、写作指南

###### 7.1 创建文章

```bash
hexo new "我的第一篇文章"
```

执行后会在 `source/_posts/` 目录下生成 `我的第一篇文章.md` 文件。

###### 7.2 文章结构

每篇文章开头是 `Front Matter`，用于设置文章属性：

```markdown
---
title: 文章标题
date: 2026-04-06 15:00:00
tags: [标签1, 标签2]
categories: 分类名
---

这里写正文内容...
```

###### 7.3 Markdown 基础语法

| 语法 | 效果 |
|------|------|
| `# 标题` | 一级标题 |
| `## 标题` | 二级标题 |
| `**粗体**` | **粗体** |
| `*斜体*` | *斜体* |
| `[链接文字](url)` | 超链接 |
| `![图片描述](图片url)` | 图片 |
| `` `代码` `` | 行内代码 |
| ` ```语言名 ` 代码块 ` ``` ` | 代码块 |
| `> 引用内容` | 引用块 |
| `- 列表项` | 无序列表 |
| `1. 列表项` | 有序列表 |

###### 7.4 插入图片

**方式一：使用图床**

推荐搭建个人图床，上传图片后获取外链，方便图片管理和文章加载：

> 📖 **延伸阅读**：[用 PicGo + Gitee 搭建个人图床](/2021/04/23/build_personal_img_bed/) — 介绍了如何使用 PicGo 工具配合 Gitee 仓库搭建免费稳定的个人图床，实现图片一键上传和链接获取。

```markdown
![图片描述](图片外链地址)
```

**方式二：本地图片**

在 `_config.yml` 中设置：

```yaml
post_asset_folder: true
```

然后使用 `hexo new` 创建文章时，会自动创建同名文件夹存放图片。引用方式：

```markdown
{% asset_img example.jpg 图片描述 %}
```

##### 8、部署博客

###### 8.1 首次部署

```bash
# 清除缓存
hexo clean

# 生成静态文件
hexo generate

# 部署到 GitHub
hexo deploy
```

或者合并命令：

```bash
hexo clean && hexo g && hexo d
```

###### 8.2 访问博客

部署完成后，访问 `https://你的用户名.github.io` 即可看到博客。

> 注意：首次部署可能需要等待几分钟才能生效。

###### 8.3 持续更新

每次修改文章或配置后，执行以下命令重新部署：

```bash
hexo clean && hexo g && hexo d
```

##### 9、绑定自定义域名（可选）

如果你有自己的域名，可以绑定到 GitHub Pages，让博客地址更加简洁易记。

> 📖 **延伸阅读**：[GitHub Pages 绑定个人域名](/2021/01/13/github_pages_domain/) — 详细介绍了域名申请、CNAME 配置、DNS 解析（A 记录和 CNAME 记录）的完整流程，帮助你将 `username.github.io` 替换为个性化域名。

###### 9.1 添加 CNAME 文件

在 `source` 目录下创建 `CNAME` 文件（无后缀），内容为你的域名：

```
www.yourdomain.com
```

###### 9.2 配置 DNS 解析

在域名服务商处添加 DNS 解析记录：

| 记录类型 | 主机记录 | 记录值 |
|---------|---------|--------|
| CNAME | www | 你的用户名.github.io |
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |

###### 9.3 启用 HTTPS

1. 进入 GitHub 仓库 → Settings → Pages
2. 在 "Custom domain" 处填写你的域名
3. 勾选 "Enforce HTTPS"

##### 10、博客优化

###### 10.1 安装实用插件

```bash
# 站点地图（SEO 优化）
npm install hexo-generator-sitemap --save

# RSS 订阅
npm install hexo-generator-feed --save

# 本地搜索
npm install hexo-generator-searchdb --save
```

在 `_config.yml` 中添加配置：

```yaml
# 站点地图
sitemap:
  path: sitemap.xml

# RSS
feed:
  type: atom
  path: atom.xml
  limit: 20

# 本地搜索
search:
  path: search.xml
  field: post
  content: true
```

###### 10.2 NexT 主题开启搜索

在 `_config.next.yml` 中启用本地搜索：

```yaml
# 本地搜索
local_search:
  enable: true
```

> 📖 **延伸阅读**：[NexT 主题集成搜索功能](/2020/05/03/next_search_service/) — 介绍了 NexT 主题集成 Local Search 搜索服务的详细配置步骤，支持标题检索和内容检索，方便读者快速查找文章。

###### 10.3 添加统计功能

可以使用 [不蒜子](https://busuanzi.ibruce.info/) 添加访问统计：

```yaml
# 在 _config.next.yml 中
busuanzi_count:
  enable: true
  total_visitors: true
  total_visitors_icon: fa fa-user
  total_views: true
  total_views_icon: fa fa-eye
  post_views: true
  post_views_icon: fa fa-eye
```

##### 11、常见问题

###### 11.1 部署失败

**问题**：执行 `hexo d` 时报错 `ERROR Deployer not found: git`

**解决**：安装部署插件

```bash
npm install hexo-deployer-git --save
```

###### 11.2 样式不显示

**问题**：本地预览正常，部署后样式丢失

**解决**：检查 `_config.yml` 中的 `url` 和 `root` 配置：

```yaml
url: https://你的用户名.github.io
root: /
```

###### 11.3 中文乱码

**问题**：文件编码不是 UTF-8 导致中文乱码

**解决**：使用编辑器（如 VS Code）将文件保存为 UTF-8 编码

###### 11.4 文章不显示

**问题**：新建的文章在博客中看不到

**解决**：
1. 检查文件是否在 `source/_posts` 目录
2. 确认文章内有正确的 `Front Matter`
3. 执行 `hexo clean && hexo g` 重新生成

##### 12、总结

通过本文，你已经学会了：

- 安装和配置 `Hexo` 博客框架
- 创建和配置 `GitHub Pages` 仓库
- 安装和配置 `NexT` 主题
- 使用 `Markdown` 写作
- 部署博客到 `GitHub Pages`
- 绑定自定义域名
- 常用插件和优化技巧