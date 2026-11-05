/* global hexo */

'use strict';

const crypto = require('crypto');

hexo.extend.helper.register('next_inject', function(point) {
  return hexo.theme.config.injects[point]
    .map(item => this.partial(item.layout, item.locals, item.options))
    .join('');
});

hexo.extend.helper.register('next_js', function(...urls) {
  const { js } = hexo.theme.config;
  return urls.map(url => this.js(`${js}/${url}`)).join('');
});

hexo.extend.helper.register('next_vendors', function(url) {
  if (url.startsWith('//')) return url;
  const internal = hexo.theme.config.vendors._internal;
  return this.url_for(`${internal}/${url}`);
});

hexo.extend.helper.register('post_edit', function(src) {
  const theme = hexo.theme.config;
  if (!theme.post_edit.enable) return '';
  return this.next_url(theme.post_edit.url + src, '<i class="fa fa-pencil"></i>', {
    class: 'post-edit-link',
    title: this.__('post.edit')
  });
});

hexo.extend.helper.register('post_nav', function(post) {
  const theme = hexo.theme.config;
  if (theme.post_navigation === false || (!post.prev && !post.next)) return '';
  const prev = theme.post_navigation === 'right' ? post.prev : post.next;
  const next = theme.post_navigation === 'right' ? post.next : post.prev;
  const left = prev ? `
    <a href="${this.url_for(prev.path)}" rel="prev" title="${prev.title}">
      <i class="fa fa-chevron-left"></i> ${prev.title}
    </a>` : '';
  const right = next ? `
    <a href="${this.url_for(next.path)}" rel="next" title="${next.title}">
      ${next.title} <i class="fa fa-chevron-right"></i>
    </a>` : '';
  return `
    <div class="post-nav">
      <div class="post-nav-item">${left}</div>
      <div class="post-nav-item">${right}</div>
    </div>`;
});

hexo.extend.helper.register('gitalk_md5', function(path) {
  let str = this.url_for(path);
  str.replace('index.html', '');
  return crypto.createHash('md5').update(str).digest('hex');
});

hexo.extend.helper.register('canonical', function() {
  // https://support.google.com/webmasters/answer/139066
  const { permalink } = hexo.config;
  let url = this.url.replace(/index\.html$/, '');
  if (!permalink.endsWith('.html')) {
    url = url.replace(/\.html$/, '');
  }
  return `<link rel="canonical" href="${url}">`;
});

/**
 * Get page path for a given language tag.
 *
 * Derives the current path from `this.url`, rewrites the language prefix,
 * and handles the `-en` filename suffix used for English post files.
 * The `-en` suffix is only added/removed on post pages (YYYY/MM/DD/slug).
 */
hexo.extend.helper.register('i18n_path', function (language) {
  var urlStr = this.url || '';
  var pathname = urlStr;
  try { pathname = new URL(urlStr).pathname; } catch (e) { /* keep as-is */ }
  if (!pathname) pathname = '/';

  var languages = this.languages || [];
  var defaultLang = languages[0] || 'zh-CN';

  // Strip index.html for cleaner manipulation; re-append later
  var hasIndexHtml = /\/index\.html$/.test(pathname);
  var workPath = pathname.replace(/\/index\.html$/, '/');

  // Determine current page language from URL pathname
  var pathWithoutLang = workPath;
  for (var i = 0; i < languages.length; i++) {
    var l = languages[i];
    var prefix = '/' + l + '/';
    if (workPath.indexOf(prefix) === 0) {
      pathWithoutLang = workPath.slice(l.length + 1);
      break;
    }
  }

  // Detect if this is a post page (path starts with /YYYY/MM/DD/ or YYYY/MM/DD/)
  var isPost = /^\/?\d{4}\/\d{2}\/\d{2}\//.test(pathWithoutLang);

  var targetPath;
  if (language === defaultLang) {
    // Switching to default lang: remove `-en` suffix from last segment (posts only)
    targetPath = isPost ? pathWithoutLang.replace(/-en(\/?)$/, '$1') : pathWithoutLang;
  } else {
    // Switching to non-default lang
    if (isPost) {
      // Add `-en` suffix to post slug if not present
      var withSuffix = /-en(\/?)$/.test(pathWithoutLang) ? pathWithoutLang : pathWithoutLang.replace(/(\/?)$/, '-en$1');
      targetPath = '/' + language + withSuffix;
    } else {
      // Non-post: just add language prefix
      targetPath = '/' + language + pathWithoutLang;
    }
  }

  if (hasIndexHtml) {
    targetPath = targetPath.replace(/\/$/, '') + '/index.html';
  }

  return this.url_for(targetPath);
});

/**
 * Get the language name
 */
hexo.extend.helper.register('language_name', function(language) {
  const name = hexo.theme.i18n.__(language)('name');
  return name === 'name' ? language : name;
});
