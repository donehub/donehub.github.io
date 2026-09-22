/* global hexo */
'use strict';

var lodash = require('lodash');

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

hexo.extend.helper.register('lang_home', function (lang) {
  var root = this.config.root || '/';
  var defaultLang = ([].concat(this.config.language || []))[0];
  if (!lang || lang === defaultLang) return root;
  return root + lang + '/';
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

  function getAlternatePosts(label) {
    return posts
      .filter(function (p) { return p.label === label; })
      .map(function (p) {
        return { title: p.title, lang: p.lang, path: p.path };
      });
  }

  function resolvePath(post) {
    if (post.lang && post.lang !== defaultLang) {
      return post.lang + '/' + post.path;
    }
    return post.path;
  }

  // Build prev/next links per language
  var i, j, post;
  for (i = 0; i < length; i++) {
    post = posts[i];
    if (post.lang) {
      for (j = i - 1; j >= 0 && !post.prev; j--) {
        if (post.lang === posts[j].lang) post.prev = posts[j];
      }
      for (j = i + 1; j < length && !post.next; j++) {
        if (post.lang === posts[j].lang) post.next = posts[j];
      }
    } else {
      if (i) post.prev = posts[i - 1];
      if (i < length - 1) post.next = posts[i + 1];
    }
    if (post.label && post.lang) {
      post.alternates = getAlternatePosts(post.label);
    }
  }

  return posts.map(function (post) {
    var layout = post.layout;
    var path = resolvePath(post);
    var layouts = ['post', 'page', 'index'];

    if (!layout || layout === 'false') {
      return { path: path, data: post.content };
    }

    if (layout !== 'post') layouts.unshift(layout);

    return {
      path: path,
      layout: layouts,
      data: lodash.extend({ __post: true }, post, { path: path })
    };
  });
});
