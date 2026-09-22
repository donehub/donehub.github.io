---
title: Building a Personal Blog with Hexo and GitHub Pages
date: 2020-03-20
lang: en
label: 000_hexo-github-pages-guide
tags: Hexo
categories: Blog Setup
---

------

<!-- more -->
##### 1. Why Build a Personal Blog

A personal blog gives you several things that third-party platforms can't:

- **A knowledge base you actually own.** Writing things up forces you to organize your thinking, and you'll thank yourself later when you need to look something up.
- **A public portfolio.** Potential employers, collaborators, or clients can see how you think and what you know.
- **Full control.** No algorithm changes, no platform shutdowns, no content policy surprises. It's yours.
- **Near-zero cost.** GitHub Pages hosts static sites for free.

There are plenty of static site generators out there — `Hugo`, `Jekyll`, `Hexo`, `WordPress`, and more. I went with `Hexo` because it runs on `Node.js`, which I was already familiar with, and it checks all the boxes:

- Fast static page generation
- A large selection of themes with deep customization options
- Markdown-first writing
- One-command deployment to GitHub Pages

This guide walks through the entire process from scratch.

##### 2. Prerequisites

###### 2.1 Install Node.js

`Hexo` requires `Node.js`. Head to the [Node.js website](https://nodejs.org/) and grab the LTS release — `18.x` or `20.x` will work fine. Run the installer and accept the defaults.

**Verify the installation:**

Open a terminal and run:

```bash
node -v
npm -v
```

You should see version numbers printed back:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2026/04/node_version.png)

###### 2.2 Install Git

You'll need `Git` to push your blog to `GitHub`. Download it from [git-scm.com](https://git-scm.com/download/win) and install with the default options.

**Verify:**

```bash
git --version
```

If it prints a version number, you're good.

###### 2.3 Set Up a GitHub Account and SSH Keys

If you don't already have one, sign up at [GitHub](https://github.com/). Then set up SSH keys so you can deploy without typing your password every time.

**Generate an SSH key pair:**

```bash
# Set your Git identity
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

# Generate the key
ssh-keygen -t rsa -C "you@example.com"
```

Hit Enter three times to accept the defaults. Your keys land in `~/.ssh/` (on Windows, that's `C:\Users\YourName\.ssh`).

**Add the public key to GitHub:**

1. Open `~/.ssh/id_rsa.pub` and copy everything in it
2. On GitHub, go to **Settings → SSH and GPG keys → New SSH key**
3. Paste the key and save

**Test the connection:**

```bash
ssh -T git@github.com
```

If you see `Hi YourName! You've successfully authenticated...`, you're all set.

##### 3. Install Hexo

###### 3.1 Create a Project Directory

Pick somewhere to keep your blog files. I'll use `D:\Blog` for this guide:

```bash
D:
mkdir myblog
cd myblog
```

###### 3.2 Install the Hexo CLI

```bash
npm install -g hexo-cli
```

Verify:

```bash
hexo -v
```

###### 3.3 Initialize the Blog

```bash
hexo init blog
cd blog
npm install
```

After initialization, your directory looks like this:

```
blog
├── _config.yml      # Site configuration
├── package.json     # Dependencies
├── scaffolds        # Post templates
├── source           # Content
│   ├── _drafts      # Drafts
│   └── _posts       # Published posts
└── themes           # Theme files
```

###### 3.4 Preview Locally

```bash
hexo server
# or simply: hexo s
```

Open `http://localhost:4000` in your browser. You should see the default Hexo landing page:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2026/04/hexo_init_page.png)

Press `Ctrl + C` to stop the server.

##### 4. Set Up GitHub Pages

###### 4.1 Create the Repository

1. On GitHub, click **"+" → "New repository"**
2. Name it `yourusername.github.io` (replace with your actual username)
3. Set it to **Public**
4. Click **Create repository**

> The repository name must follow the `username.github.io` pattern — that's how GitHub Pages knows it's a user site.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2026/04/github_create_repo.png)

###### 4.2 Configure Deployment

Open `_config.yml` in your blog's root directory. Find the `deploy` section and update it:

```yaml
# Deployment
deploy:
  type: git
  repo: git@github.com:yourusername/yourusername.github.io.git
  branch: master
```

For example, if your username is `donehub`:

```yaml
deploy:
  type: git
  repo: git@github.com:donehub/donehub.github.io.git
  branch: master
```

###### 4.3 Install the Deploy Plugin

```bash
npm install hexo-deployer-git --save
```

##### 5. Configure the Site

###### 5.1 Update Site Metadata

Open `_config.yml` and fill in your details:

```yaml
# Site
title: My Blog
subtitle: 'Notes on tech and life'
description: ''
keywords:
author: Your Name
language: en
timezone: 'America/New_York'

# URL
url: https://yourusername.github.io
root: /
permalink: :year/:month/:day/:title/
```

###### 5.2 Key Commands

| Command | Shortcut | What it does |
|---------|----------|--------------|
| `hexo new "Post Title"` | `hexo n "Post Title"` | Create a new post |
| `hexo generate` | `hexo g` | Build static files |
| `hexo server` | `hexo s` | Start local preview server |
| `hexo deploy` | `hexo d` | Push to GitHub Pages |
| `hexo clean` | — | Clear the cache |

The most common combo:

```bash
hexo clean && hexo g && hexo d
```

##### 6. Install a Theme

The default Hexo theme is bare-bones. I'd recommend [`NexT`](https://github.com/next-theme/hexo-theme-next) — it's clean, well-maintained, and highly configurable.

###### 6.1 Install NexT

```bash
npm install hexo-theme-next --save
```

Or clone it directly:

```bash
cd blog
git clone https://github.com/next-theme/hexo-theme-next.git themes/next
```

###### 6.2 Activate the Theme

In `_config.yml`, change:

```yaml
theme: next
```

###### 6.3 Theme Configuration

NexT has its own config file. Create `_config.next.yml` in the site root:

```yaml
# Pick a layout scheme
scheme: Muse          # Clean default
# scheme: Mist        # Even more minimal
# scheme: Pisces      # Two-column layout
# scheme: Gemini      # Refined two-column

# Navigation menu
menu:
  home: / || fa fa-home
  archives: /archives/ || fa fa-archive
  tags: /tags/ || fa fa-tags
  categories: /categories/ || fa fa-th
  about: /about/ || fa fa-user

# Social links in the sidebar
social:
  GitHub: https://github.com/yourusername || fab fa-github

# Avatar
avatar:
  url: /images/avatar.png
  rounded: true
  opacity: 1

# Code highlighting
codeblock:
  theme:
    light: default
    dark: stackoverflow-dark
```

###### 6.4 Create Category and Tag Pages

```bash
hexo new page categories
hexo new page tags
hexo new page about
```

Edit `source/categories/index.md`:

```markdown
---
title: Categories
date: 2026-04-06 15:00:00
type: "categories"
---
```

Edit `source/tags/index.md`:

```markdown
---
title: Tags
date: 2026-04-06 15:00:00
type: "tags"
---
```

##### 7. Writing Posts

###### 7.1 Create a Post

```bash
hexo new "My First Post"
```

This creates `source/_posts/My-First-Post.md`.

###### 7.2 Post Structure

Every post starts with a Front Matter block:

```markdown
---
title: My First Post
date: 2026-04-06 15:00:00
tags: [tag1, tag2]
categories: Category Name
---

Your content goes here...
```

###### 7.3 Markdown Cheat Sheet

| Syntax | Result |
|--------|--------|
| `# Heading` | H1 |
| `## Heading` | H2 |
| `**bold**` | **bold** |
| `*italic*` | *italic* |
| `[link text](url)` | Hyperlink |
| `![alt text](image-url)` | Image |
| `` `inline code` `` | Inline code |
| ` ```lang ` code block ` ``` ` | Fenced code block |
| `> blockquote` | Blockquote |
| `- item` | Unordered list |
| `1. item` | Ordered list |

###### 7.4 Working with Images

**Option 1: Use an image host**

An image host gives you stable URLs that you can reference from anywhere. This keeps your repo small and your pages fast.

> 📖 **Related reading:** [Building a Personal Image Host with PicGo and Gitee](/2021/04/23/build_personal_img_bed/) — covers setting up a free image hosting solution using PicGo and a Gitee repository.

```markdown
![Alt text](https://your-image-host.com/path/to/image.png)
```

**Option 2: Store images locally**

Enable post asset folders in `_config.yml`:

```yaml
post_asset_folder: true
```

Now `hexo new "My Post"` also creates a `My-Post/` folder next to the markdown file. Drop images there and reference them with:

```markdown
{% asset_img example.jpg Caption text %}
```

##### 8. Deploy

###### 8.1 First Deploy

```bash
hexo clean
hexo generate
hexo deploy
```

Or all at once:

```bash
hexo clean && hexo g && hexo d
```

###### 8.2 Visit Your Blog

After deploying, your blog is live at `https://yourusername.github.io`.

> The first deployment can take a few minutes to propagate.

###### 8.3 Updating

Every time you change a post or config, redeploy:

```bash
hexo clean && hexo g && hexo d
```

##### 9. Custom Domain (Optional)

If you own a domain, you can point it at your GitHub Pages site for a cleaner URL.

> 📖 **Related reading:** [Binding a Custom Domain to GitHub Pages](/2021/01/13/github_pages_domain/) — walks through CNAME setup, DNS records (A and CNAME), and HTTPS configuration.

###### 9.1 Add a CNAME File

Create a file called `CNAME` (no extension) in the `source/` directory:

```
www.yourdomain.com
```

###### 9.2 Configure DNS

Add these records at your domain registrar:

| Type | Host | Value |
|------|------|-------|
| CNAME | www | yourusername.github.io |
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |

###### 9.3 Enable HTTPS

1. Go to your repo → **Settings → Pages**
2. Enter your domain under **Custom domain**
3. Check **Enforce HTTPS**

##### 10. Useful Plugins

###### 10.1 Recommended Packages

```bash
# Sitemap for SEO
npm install hexo-generator-sitemap --save

# RSS feed
npm install hexo-generator-feed --save

# Full-text search
npm install hexo-generator-searchdb --save
```

Add to `_config.yml`:

```yaml
# Sitemap
sitemap:
  path: sitemap.xml

# RSS
feed:
  type: atom
  path: atom.xml
  limit: 20

# Search
search:
  path: search.xml
  field: post
  content: true
```

###### 10.2 Enable Search in NexT

In `_config.next.yml`:

```yaml
local_search:
  enable: true
```

> 📖 **Related reading:** [Integrating Search into NexT](/2020/05/03/next_search_service/) — detailed setup for NexT's Local Search, covering title and content indexing.

###### 10.3 Add Visitor Statistics

[Busuanzi](https://busuanzi.ibruce.info/) is a lightweight analytics counter:

```yaml
# In _config.next.yml
busuanzi_count:
  enable: true
  total_visitors: true
  total_visitors_icon: fa fa-user
  total_views: true
  total_views_icon: fa fa-eye
  post_views: true
  post_views_icon: fa fa-eye
```

##### 11. Troubleshooting

###### 11.1 Deploy Fails with "Deployer not found: git"

Install the Git deployer:

```bash
npm install hexo-deployer-git --save
```

###### 11.2 Styles Missing After Deploy

Local preview looks fine but the live site has no CSS. Check `_config.yml`:

```yaml
url: https://yourusername.github.io
root: /
```

A wrong `url` or `root` value breaks all asset paths.

###### 11.3 Garbled Characters

Your editor is saving files in a non-UTF-8 encoding. Switch your editor (VS Code, for example) to save as UTF-8.

###### 11.4 New Post Doesn't Show Up

1. Make sure the file is in `source/_posts/`
2. Verify the Front Matter is valid YAML
3. Run `hexo clean && hexo g` to force a rebuild

##### 12. Wrap-Up

By now you've covered the full workflow: installing `Hexo`, setting up a `GitHub Pages` repo, configuring the `NexT` theme, writing in `Markdown`, deploying, and adding a custom domain. You also have a few plugins for search, RSS, and analytics. From here, the best thing to do is start writing — the rest will come naturally.
