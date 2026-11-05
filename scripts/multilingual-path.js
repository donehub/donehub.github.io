/* global hexo */
'use strict';

var lodash = require('lodash');
var path = require('path');

/**
 * Detect post language from filename when `post.lang` is not set.
 * Files ending with `-en` (before extension) are English; rest are default.
 */
function detectLang(post, defaultLang) {
  if (post.lang) return post.lang;
  var source = post.source || '';
  var basename = path.basename(source, path.extname(source));
  return basename.endsWith('-en') ? 'en' : defaultLang;
}

/**
 * Detect post label from filename when `post.label` is not set.
 * Label is the basename without extension and without `-en` suffix.
 */
function detectLabel(post) {
  if (post.label) return post.label;
  var source = post.source || '';
  var basename = path.basename(source, path.extname(source));
  return basename.endsWith('-en') ? basename.slice(0, -3) : basename;
}

/**
 * Register a `site_lang` helper that returns the primary site language
 * (first element of the language array). Used by templates to render
 * <html lang="..."> correctly when `language` is an array.
 *
 * Register a `lang_home` helper that returns the home page path for a
 * given language code. E.g. lang_home('en') → '/en/'.
 */
hexo.extend.helper.register('site_lang', function () {
  var languages = [].concat(this.config.language || []);
  return languages[0] || 'en';
});

/**
 * Resolve the language of the page currently being rendered.
 *
 * Prefers `page.lang` (set by the i18n generators); falls back to the
 * language prefix of the page path (static pages like /en/tags/ have no
 * `lang` field); falls back to the default language.
 */
function resolvePageLang(locals) {
  var languages = [].concat(locals.config.language || []);
  var defaultLang = languages[0];
  var page = locals.page || {};

  if (page.lang) return page.lang;

  var pagePath = '/' + String(page.path || '').replace(/^\/+/, '');
  for (var i = 1; i < languages.length; i++) {
    if (pagePath.indexOf('/' + languages[i] + '/') === 0) return languages[i];
  }
  return defaultLang;
}

hexo.extend.helper.register('current_lang', function () {
  return resolvePageLang(this);
});

/**
 * Prefix an internal link with the current page language, so nav items keep
 * the visitor inside the language they picked. On /en/archives/,
 * lang_url('/tags/') → '/en/tags/'.
 */
hexo.extend.helper.register('lang_url', function (targetPath) {
  if (!targetPath || typeof targetPath !== 'string') return targetPath;
  // Leave external links and relative/anchor paths alone
  if (/^([a-z][a-z0-9+.-]*:)?\/\//i.test(targetPath)) return targetPath;
  if (targetPath.charAt(0) !== '/') return targetPath;

  var defaultLang = ([].concat(this.config.language || []))[0];
  var lang = resolvePageLang(this);
  if (!lang || lang === defaultLang) return targetPath;

  return '/' + lang + targetPath;
});

/**
 * Split the current page path into segments, dropping the language prefix.
 *
 * `en/about/index.html` → { prefix: 'en', paths: ['about', 'index.html'] }
 *
 * The breadcrumb partial counts segments to decide whether a page is nested,
 * so a language prefix must not count as an extra directory level.
 */
hexo.extend.helper.register('page_path_segments', function () {
  var segments = String((this.page && this.page.path) || '').split('/');
  var defaultLang = ([].concat(this.config.language || []))[0];
  var lang = resolvePageLang(this);
  var prefix = '';

  if (lang && lang !== defaultLang && segments[0] === lang) {
    prefix = segments.shift();
  }

  return { prefix: prefix, paths: segments };
});

hexo.extend.helper.register('lang_home', function (lang) {
  var root = this.config.root || '/';
  var defaultLang = ([].concat(this.config.language || []))[0];
  if (!lang || lang === defaultLang) return root;
  return root + lang + '/';
});

/**
 * Count posts for a specific language.
 * Detects language from filename when `post.lang` is not set.
 */
hexo.extend.helper.register('lang_post_count', function (lang) {
  var defaultLang = ([].concat(this.config.language || []))[0];
  var posts = this.site.posts;
  if (!posts || !posts.length) return 0;
  return posts.filter(function (post) {
    return detectLang(post, defaultLang) === lang;
  }).length;
});

/**
 * Custom multilingual post generator.
 *
 * Overrides the default post generator to support language-prefixed URLs.
 * Posts with `lang` set to a non-default language get their path prefixed
 * with the language code (e.g. /en/2026/09/12/my-post/).
 *
 * Also implements:
 *  - prev/next navigation within the same language
 *  - alternate post linking via the `label` field (same label = same post
 *    in different languages)
 */
hexo.extend.generator.register('post', function (locals) {
  var config = this.config;
  var languages = [].concat(config.language || []);
  var defaultLang = languages[0];

  var posts = locals.posts.sort('-date').toArray();
  var length = posts.length;

  // Pre-compute lang and label for each post (from front-matter or filename)
  posts.forEach(function (p) {
    p._lang = detectLang(p, defaultLang);
    p._label = detectLabel(p);
  });

  function getAlternatePosts(label) {
    return posts
      .filter(function (p) { return p._label === label; })
      .map(function (p) {
        return { title: p.title, lang: p._lang, path: p.path };
      });
  }

  function resolvePath(post) {
    if (post._lang && post._lang !== defaultLang) {
      return post._lang + '/' + post.path;
    }
    return post.path;
  }

  // Build prev/next links per language
  var i, j, post;
  for (i = 0; i < length; i++) {
    post = posts[i];
    for (j = i - 1; j >= 0 && !post.prev; j--) {
      if (post._lang === posts[j]._lang) post.prev = posts[j];
    }
    for (j = i + 1; j < length && !post.next; j++) {
      if (post._lang === posts[j]._lang) post.next = posts[j];
    }
    post.alternates = getAlternatePosts(post._label);
  }

  return posts.map(function (post) {
    var layout = post.layout;
    var resolvedPath = resolvePath(post);
    var layouts = ['post', 'page', 'index'];

    // Override the computed `path` property on this post instance so that
    // templates reading `post.path` or `post.permalink` get the correct
    // language-prefixed URL.
    if (resolvedPath !== post.path) {
      Object.defineProperty(post, 'path', {
        value: resolvedPath,
        writable: true,
        configurable: true,
        enumerable: true,
      });
    }

    if (!layout || layout === 'false') {
      return { path: resolvedPath, data: post.content };
    }

    if (layout !== 'post') layouts.unshift(layout);

    return {
      path: resolvedPath,
      layout: layouts,
      data: lodash.extend({ __post: true }, post, { path: resolvedPath })
    };
  });
});
