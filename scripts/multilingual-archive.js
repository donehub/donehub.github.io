/* global hexo */
'use strict';

var path = require('path');
var pagination = require('hexo-pagination');

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
 * Custom multilingual archive generator.
 *
 * Replaces hexo-generator-archive to filter posts by language.
 *
 * Generates:
 *  - /archives/              → default language archive
 *  - /en/archives/           → English archive
 *  - /archives/2026/         → default language yearly archive
 *  - /en/archives/2026/      → English yearly archive
 *  - /archives/2026/09/      → default language monthly archive
 *  - /en/archives/2026/09/   → English monthly archive
 */

var fmtNum = function (num) {
  return num < 10 ? '0' + num : num;
};

function getArchivePages(baseUrl, lang, allPosts, config, Query) {
  var archiveDir = config.archive_dir;
  var paginationDir = config.pagination_dir || 'page';
  var result = [];

  // Filter posts by language (detect from filename if lang not set)
  var defaultLang = ([].concat(config.language || []))[0];
  var filtered = allPosts.filter(function (post) {
    return detectLang(post, defaultLang) === lang;
  });

  if (!filtered.length) return result;

  if (archiveDir[archiveDir.length - 1] !== '/') archiveDir += '/';

  var perPage = (config.archive_generator || {}).per_page;

  function generate(genPath, posts, options) {
    options = options || {};
    options.archive = true;
    options.lang = lang;
    // Total of this archive set (all pages), so the template doesn't show
    // the per-page slice length. Cannot reuse `total`, which pagination
    // already uses for the page count.
    options.post_count = posts.length;

    result = result.concat(pagination(genPath, posts, {
      perPage: perPage,
      layout: ['archive', 'index'],
      format: paginationDir + '/%d/',
      data: options
    }));
  }

  var sortedFiltered = filtered.sort('-date');
  generate(baseUrl, sortedFiltered);

  var archiveGenerator = config.archive_generator || {};
  if (!archiveGenerator.yearly) return result;

  var posts = {};

  sortedFiltered.forEach(function (post) {
    var date = post.date;
    var year = date.year();
    var month = date.month() + 1;

    if (!Object.prototype.hasOwnProperty.call(posts, year)) {
      posts[year] = [
        [], [], [], [], [], [], [], [], [], [], [], [], []
      ];
    }

    posts[year][0].push(post);
    posts[year][month].push(post);

    if (archiveGenerator.daily) {
      var day = date.date();
      if (!Object.prototype.hasOwnProperty.call(posts[year][month], 'day')) {
        posts[year][month].day = {};
      }
      (posts[year][month].day[day] || (posts[year][month].day[day] = [])).push(post);
    }
  });

  var years = Object.keys(posts);
  var year, data, month, monthData, url;

  for (var i = 0, len = years.length; i < len; i++) {
    year = +years[i];
    data = posts[year];
    url = baseUrl + year + '/';
    if (!data[0].length) continue;

    generate(url, new Query(data[0]), { year: year, lang: lang });

    if (!archiveGenerator.monthly && !archiveGenerator.daily) continue;

    for (month = 1; month <= 12; month++) {
      monthData = data[month];
      if (!monthData.length) continue;

      if (archiveGenerator.monthly) {
        generate(url + fmtNum(month) + '/', new Query(monthData), {
          year: year,
          month: month,
          lang: lang
        });
      }

      if (!archiveGenerator.daily) continue;

      for (var day = 1; day <= 31; day++) {
        var dayData = monthData.day[day];
        if (!dayData || !dayData.length) continue;
        generate(url + fmtNum(month) + '/' + fmtNum(day) + '/', new Query(dayData), {
          year: year,
          month: month,
          day: day,
          lang: lang
        });
      }
    }
  }

  return result;
}

// Unregister the default archive generator so it doesn't duplicate output
hexo.extend.generator.store['archive'] = undefined;

// Ensure archive_generator config has defaults (in case the plugin didn't set them)
hexo.config.archive_generator = Object.assign({
  per_page: typeof hexo.config.per_page === 'undefined' ? 10 : hexo.config.per_page,
  yearly: true,
  monthly: true,
  daily: false
}, hexo.config.archive_generator);

hexo.extend.generator.register('archive', function () {
  var config = this.config;
  var allPosts = this.locals.get('posts').sort('-date');
  var archiveDir = config.archive_dir;
  var languages = [].concat(config.language || []).filter(function (l) {
    return l !== 'default';
  });
  var defaultLang = languages[0];
  var Query = this.model('Post').Query;

  var archivePages = [];

  languages.forEach(function (lang) {
    var baseUrl;
    if (lang === defaultLang) {
      baseUrl = archiveDir;
    } else {
      baseUrl = lang + '/' + archiveDir;
    }
    // Ensure trailing slash for proper URL concatenation
    if (baseUrl[baseUrl.length - 1] !== '/') baseUrl += '/';
    archivePages = archivePages.concat(getArchivePages(baseUrl, lang, allPosts, config, Query));
  });

  return archivePages;
});
