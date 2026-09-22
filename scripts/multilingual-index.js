/* global hexo */
'use strict';

var pagination = require('hexo-pagination');
var path = require('path');

/**
 * Custom multilingual index generator.
 *
 * Replaces hexo-generator-index-i18n to handle posts without a `lang` field
 * (treats them as the default language).
 *
 * Generates:
 *  - /            → default language (zh-CN) index
 *  - /en/         → English index
 *  - /page/2/ ... → paginated default language pages
 *  - /en/page/2/  → paginated English pages
 */
function getIndexPages(baseUrl, lang, posts, config) {
  var paginationDir = config.pagination_dir || 'page';
  var defaultLang = [].concat(config.language || [])[0];

  // Include posts where lang matches, OR posts without a lang field
  // (those are treated as the default language)
  var filtered = posts.filter(function (post) {
    if (!post.lang) return lang === defaultLang;
    return post.lang === lang;
  });

  return pagination(baseUrl, filtered, {
    perPage: config.index_generator.per_page,
    layout: ['index'],
    format: paginationDir + '/%d/',
    data: {
      __index: true,
      lang: lang,
    },
  });
}

hexo.config.index_generator = Object.assign({
  per_page: typeof hexo.config.per_page === 'undefined' ? 10 : hexo.config.per_page,
  order_by: '-date',
}, hexo.config.index_generator);

hexo.extend.generator.register('index-i18n', function () {
  var config = this.config;
  var posts = this.locals.get('posts').sort(config.index_generator.order_by);
  var indexPath = config.index_generator.path || '';
  var languages = [].concat(config.language || []).filter(function (l) {
    return l !== 'default';
  });
  var defaultLang = languages[0];

  var indexPages = [];

  // Generate per-language index pages at /<lang>/ (skip default, it goes to root)
  languages.forEach(function (lang) {
    if (lang === defaultLang) return;
    var baseUrl = path.join(lang, indexPath);
    indexPages = indexPages.concat(getIndexPages(baseUrl, lang, posts, config));
  });

  // Generate root index for default language
  if (defaultLang) {
    indexPages = indexPages.concat(getIndexPages(indexPath, defaultLang, posts, config));
  }

  return indexPages;
});
