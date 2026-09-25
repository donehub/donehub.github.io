---
title: The Complete Guide to Blog SEO Optimization: From Webmaster Verification to Search Engine Indexing
date: 2021-01-14
tags: SEO
categories: Blog Setup
lang: en
label: 019_blog-seo-optimization-guide
---

> After setting up a blog, many people find that search engines can't find their articles. The problem isn't article quality; search engines simply don't know your site exists. This guide uses Hexo + NexT theme as an example and walks through the full SEO optimization process: webmaster verification, Sitemap configuration, auto-push, and how it all works under the hood.

<!-- more -->

## 1. What Is SEO and Why Does It Matter

**SEO (Search Engine Optimization)** is the practice of making your website visible to search engines like Google, Baidu, and Bing, so they can discover, index, and rank your content.

### What Happens Without SEO

| Scenario | Outcome |
|------|------|
| You write a high-quality tech article | Search engines can't find it; no one discovers it |
| Your blog has been running for a year | Only people who type the URL directly can see it |
| You want more people to see your content | You have to share manually, with limited reach |

### What SEO Gets You

| Scenario | Outcome |
|------|------|
| Search engines index your site | Users searching relevant keywords can find you |
| You consistently publish quality content | Your search ranking gradually improves |
| Search engines trust your site | New articles get indexed faster |

---

## 2. The Three Core Steps of SEO

```
Step 1: Let search engines know your site exists → Webmaster verification
Step 2: Tell search engines what pages you have → Sitemap
Step 3: Actively push new content to search engines → Auto-push
```

### How Search Engines Work

```
┌─────────────────────────────────────────────────────────────┐
│                  Search Engine Workflow                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Discovery                                                │
│     └── Webmaster verification: You tell the search engine   │
│         "my site exists"                                     │
│                                                             │
│  2. Crawling                                                 │
│     └── Sitemap: You provide a site map listing all pages    │
│                                                             │
│  3. Indexing                                                 │
│     └── The search engine analyzes page content and stores   │
│         it in its database                                   │
│                                                             │
│  4. Ranking                                                  │
│     └── When users search, results are ranked by algorithm   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Step One: Webmaster Verification

The essence of webmaster verification: **proving to search engines that you own the site**.

### Why Verify

Search engines don't just index any site. They need to confirm:
- Who owns the site
- Whether you have authority to manage it
- Whether the site is trustworthy

Once verified, you get management privileges:
- Submit Sitemaps
- View indexing status
- View search traffic data
- Request faster indexing

---

## 4. Google Search Console Setup

### 4.1 Access Google Search Console

Visit: https://search.google.com/search-console

You'll need a Google account.

### 4.2 Choose a Property Type

Google offers two property types:

| Type | Description | Best For |
|------|------|---------|
| **Domain** | Covers all subdomains (www, m, etc.) | DNS verification; good if you manage your own DNS |
| **URL Prefix** | Covers only the specified URL | Multiple verification methods; recommended for beginners |

**Choose "URL Prefix"** and enter your blog URL, e.g.:
```
https://your-blog.github.io/
```

### 4.3 Choose HTML Tag Verification

After selecting "URL Prefix", Google shows several verification methods:

| Method | Description | Recommended |
|------|------|:----:|
| HTML file | Upload an HTML file to your site | ❌ May be overwritten on deploy |
| **HTML tag** | Add a meta tag to your homepage `<head>` | ✓ Built-in support in NexT theme |
| Google Analytics | Verify using your GA account | ❌ Requires GA to be configured first |
| Google Tag Manager | Verify using your GTM account | ❌ Requires GTM to be configured first |

Select **"HTML tag"** and you'll see something like:
```html
<meta name="google-site-verification" content="xxxxxxxxxxxxx" />
```

### 4.4 Configure in Your Blog

**NexT theme configuration:**

Edit `themes/next/_config.yml` and find:
```yaml
google_site_verification:
```

Paste the verification code (the `content` attribute value):
```yaml
google_site_verification: xxxxxxxxxxxxx
```

**What's the verification code?**

From this snippet:
```html
<meta name="google-site-verification" content="8GnrAdfl7gO-GxPzgsB1kmX6vAeJLAX8B8-vFdpAmi4" />
```

The code is the value inside `content="..."`:
```
8GnrAdfl7gO-GxPzgsB1kmX6vAeJLAX8B8-vFdpAmi4
```

### 4.5 Deploy and Verify

```bash
hexo clean
hexo generate
hexo deploy
```

After deployment, go back to Google Search Console and click the "Verify" button.

### 4.6 What You Get After Verification

| Feature | Description |
|------|------|
| **Submit Sitemap** | Tell Google about all your pages |
| **Indexing status** | See which pages are indexed |
| **Search traffic** | See what keywords users use to find you |
| **Crawl stats** | Monitor Googlebot activity |
| **Issue detection** | Find problems like 404 pages |
| **Request indexing** | Ask Google to index new articles faster |

---

## 5. Baidu Webmaster Verification Setup

### 5.1 Access Baidu Webmaster Platform

Visit: https://ziyuan.baidu.com/site

You'll need a Baidu account.

### 5.2 Add Your Site

Click "Add Site" and enter your blog URL:
```
https://your-blog.github.io/
```

### 5.3 Choose HTML Tag Verification

Baidu offers three verification methods:

| Method | Description | Recommended |
|------|------|:----:|
| File verification | Upload an HTML file | ❌ May be overwritten on deploy |
| **HTML tag** | Add a meta tag to your homepage | ✓ Built-in support in NexT theme |
| CNAME verification | Add a DNS record | ❌ Requires DNS management access |

Select **"HTML tag"** and you'll see something like:
```html
<meta name="baidu-site-verification" content="codeva-xxxxx" />
```

### 5.4 Configure in Your Blog

Edit `themes/next/_config.yml` and find:
```yaml
baidu_site_verification:
```

Paste the verification code:
```yaml
baidu_site_verification: codeva-xxxxx
```

### 5.5 Deploy and Verify

```bash
hexo clean
hexo generate
hexo deploy
```

After deployment, go back to the Baidu platform and click "Verify".

### 5.6 What You Get After Verification

| Feature | Description |
|------|------|
| **Link submission** | Push URLs directly to Baidu |
| **Sitemap submission** | Submit your site map |
| **Indexing query** | Check what Baidu has indexed |
| **Index volume** | See how many pages are indexed |
| **Crawl frequency** | How often Baidubot visits |
| **Site diagnostics** | Identify site issues |

---

## 6. Step Two: Configure Your Sitemap

### What Is a Sitemap

A Sitemap is an XML file that lists all the URLs on your site.

```
Example sitemap.xml content:

https://your-blog.github.io/2026/05/16/article-1/
https://your-blog.github.io/2026/05/15/article-2/
https://your-blog.github.io/2026/05/14/article-3/
...
```

### Why You Need a Sitemap

Search engine crawlers discover pages in two ways:

| Method | Efficiency | Description |
|------|------|------|
| Random discovery | Low | Crawlers follow links randomly and may miss pages |
| **Sitemap** | High | You provide a complete list; crawlers work efficiently |

### Configuring Sitemap in Hexo

**Install the plugin:**
```bash
npm install hexo-generator-sitemap --save
```

**Configure `_config.yml`:**
```yaml
sitemap:
  path: sitemap.xml
```

**Access it after generation:**
```
https://your-blog.github.io/sitemap.xml
```

### Submit Your Sitemap to Search Engines

**Google Search Console:**
1. Go to → Indexing → Sitemaps
2. Enter `sitemap.xml`
3. Click Submit

**Baidu Webmaster Platform:**
1. Go to → Data Import → Link Submission → Sitemap
2. Enter `https://your-blog.github.io/sitemap.xml`
3. Click Submit

---

## 7. Step Three: Auto-Push

### What Is Auto-Push

Every time a user visits a page on your site, a request is automatically sent to the search engine: "This page has been updated; come crawl it."

### Baidu Auto-Push Configuration

The NexT theme has built-in support. Edit `themes/next/_config.yml`:
```yaml
baidu_push: true
```

Once enabled, every page will automatically include the push code:

```javascript
// Executes automatically when a user visits your page
(function(){
  var bp = document.createElement('script');
  bp.src = 'https://zz.bdstatic.com/linksubmit/push.js';
  document.body.appendChild(bp);
})();
```

### How It Works

```
User visits your blog page
       ↓
Push script runs on page load
       ↓
Script sends a request to Baidu: "This URL was visited; please crawl it"
       ↓
Baidu crawler receives the signal and schedules a crawl
       ↓
Page gets indexed faster
```

---

## 8. What Webmaster Verification Gives You Long-Term

Many people complete verification but don't know what to do next. Here's a detailed breakdown:

### 8.1 Indexing Monitoring

After verification, you can view:

| Data | Google | Baidu |
|------|:------:|:----:|
| Number of indexed pages | ✓ | ✓ |
| Unindexed pages | ✓ | ✓ |
| Indexing time | ✓ | ✓ |

**Use**: Know which articles are indexed and which aren't, so you can optimize accordingly.

### 8.2 Search Traffic Analysis

| Data | Description |
|------|------|
| Search keywords | What terms users search to find you |
| Clicks | How many times search results are clicked |
| Impressions | How many times search results are shown |
| Click-through rate | Clicks / Impressions |

**Use**: Understand user intent and optimize your article titles and content.

### 8.3 Manual Submission

After publishing a new article, you can request indexing:

**Google**: Search Console → URL Inspection → Enter URL → Request Indexing

**Baidu**: Webmaster Platform → Link Submission → Active Push

**Use**: New articles get indexed faster without waiting for random crawler discovery.

### 8.4 Issue Diagnostics

| Issue | Description |
|------|------|
| 404 pages | Broken links that hurt user experience |
| Server errors | Pages that can't be accessed |
| Mobile compatibility | Whether pages render correctly on mobile |
| Page load speed | Whether pages are too slow |

**Use**: Find and fix problems promptly to improve user experience and rankings.

---

## 9. SEO Timeline: When to Expect Results

| Timeframe | Result |
|------|------|
| Verification complete | Webmaster platform starts monitoring |
| 1–3 days | Sitemap is processed |
| 1–2 weeks | Google may start indexing some pages |
| 1–4 weeks | Baidu may start indexing some pages |
| 2–3 months | Indexing volume gradually increases |
| 6+ months | Search rankings may improve (depends on content quality) |

---

## 10. SEO Checklist

Complete in order:

- [ ] Install the sitemap plugin
- [ ] Configure `_config.yml` to generate sitemap.xml
- [ ] Complete Google Search Console verification
- [ ] Complete Baidu Webmaster Platform verification
- [ ] Submit sitemap to Google
- [ ] Submit sitemap to Baidu
- [ ] Enable Baidu auto-push
- [ ] Add RSS feed (optional)
- [ ] Configure robots.txt (optional)
- [ ] Regularly review webmaster platform data

---

## 11. FAQ

### Q1: How long until I see indexed pages after verification?

Google usually starts indexing within 1–2 weeks. Baidu may take 1–4 weeks.

### Q2: Why aren't some pages being indexed?

Possible reasons:
- Content quality issues (too thin, duplicated)
- Page structure problems (missing title, missing description)
- Low site authority (new sites need time to build trust)
- Search engine hasn't crawled the page yet

### Q3: Pages are indexed but don't show up in search?

Possible reasons:
- High keyword competition
- Content relevance is weak
- Low site authority

Solution: Optimize titles, expand content, publish consistently.

### Q4: I lost my verification code. What now?

You can re-obtain the code and re-verify. Your existing data won't be affected.

---

## 12. References

- [Google Search Console Help](https://support.google.com/webmasters/)
- [Baidu Webmaster Platform Help](https://ziyuan.baidu.com/college/index)
- [Hexo Official Docs](https://hexo.io/docs/)
- [NexT Theme Docs](https://theme-next.org/docs/)

---

## 13. Summary

The essence of SEO optimization:

> **Help search engines efficiently discover and index your content.**

Webmaster verification = Prove you own the site and get management access

Sitemap = Provide a map so crawlers can work efficiently

Auto-push = Tell search engines "come crawl" every time someone visits

Once you complete these three steps, your blog has the basic foundation for search engine indexing. The rest is up to you: consistently publish quality content and let time build your authority.
