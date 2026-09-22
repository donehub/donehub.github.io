---
title: Building a Multilingual Blog with Hexo
date: 2026-09-12
lang: en
tags: [Hexo, Blog]
categories: Blog Setup
---

This is the English version of my blog. Going forward, I will publish English translations alongside the original Chinese posts.

<!-- more -->

## Why Add English Support

Most of my technical writing has been in Chinese, targeting the Chinese developer community. But many topics I cover, such as Spring Boot configuration, database design patterns, and deployment strategies, are relevant to developers worldwide. Adding English support allows these posts to reach a broader audience.

## Technical Implementation

The blog runs on Hexo 4.2.0 with the NexT theme. Multi-language support is powered by two plugins:

- `hexo-multilingual` provides the core i18n infrastructure, including per-language configuration overrides and alternate post linking.
- `hexo-generator-index-i18n` generates separate index pages for each language, so `/` serves Chinese posts and `/en/` serves English posts.

A custom Hexo filter script automatically prepends `/en/` to the URL path of any post with `lang: en` in its front-matter. Chinese posts remain at their original URLs, so existing bookmarks and links continue to work.

## What to Expect

Not every post will have an English version. I will prioritize translating posts that cover general software engineering topics. Posts about China-specific infrastructure or Chinese-language tooling will stay in Chinese only.
