<style>
/* Header Language Switcher */
.menu-item-languages { position: relative; cursor: pointer; }
.lang-switch-btn {
  display: flex; align-items: center; gap: 4px;
  color: inherit; text-decoration: none; font-size: 14px;
  line-height: 20px; padding: 0; border: none; background: none; cursor: pointer;
  font-family: inherit;
}
.lang-switch-btn:hover { color: #fc6423; }
.lang-switch-btn .fa { font-size: 16px; }
.lang-dropdown {
  display: none; position: absolute; top: 100%; right: 0;
  background: #fff; border: 1px solid #ddd; border-radius: 4px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.12); min-width: 120px;
  z-index: 1000; overflow: hidden; padding-top: 4px;
}
.menu-item-languages:hover .lang-dropdown { display: block; }
.lang-dropdown a {
  display: block; padding: 8px 16px; color: #555;
  text-decoration: none; font-size: 14px; white-space: nowrap;
  transition: background 0.15s;
}
.lang-dropdown a:hover { background: #f5f5f5; color: #222; }
.lang-dropdown a.active { color: #fc6423; font-weight: 600; }
@media (max-width: 767px) {
  .menu-item-languages { margin-top: 5px; }
  .lang-dropdown { position: static; box-shadow: none; border: none; padding-left: 20px; }
  .menu-item-languages:hover .lang-dropdown { display: block; }
}
</style>
<script>
(function() {
  // Hexo pushes its theme-strings fallback into config.language in place
  // (theme/index.js), so `default` shows up here too and must be dropped.
  var LANGS = [].concat({{ config.language | json }}).filter(function(lang) {
    return lang && lang !== 'default';
  });
  var DEFAULT_LANG = LANGS[0];
  var STORAGE_KEY = 'donehub_lang';

  function storeLang(lang) {
    try { localStorage.setItem(STORAGE_KEY, lang); } catch(e) {}
  }

  function getStoredLang() {
    try { return localStorage.getItem(STORAGE_KEY); } catch(e) { return null; }
  }

  function detectBrowserLang() {
    var raw = (navigator.language || navigator.userLanguage || '').toLowerCase();
    return (LANGS.indexOf('en') !== -1 && raw.indexOf('en') === 0) ? 'en' : DEFAULT_LANG;
  }

  function siteRoot() {
    // CONFIG is defined at the end of <body>, so it is still undefined while
    // this script parses; the redirect below falls back to the site root.
    var value = (typeof CONFIG !== 'undefined' && CONFIG.root) || '/';
    if (value.charAt(0) !== '/') value = '/' + value;
    return value.charAt(value.length - 1) === '/' ? value : value + '/';
  }

  // Site root is stripped from every path we manipulate, and put back on the way out.
  function stripRoot(path) {
    var root = siteRoot();
    if (root !== '/' && path.indexOf(root) === 0) return '/' + path.slice(root.length);
    return path;
  }

  function addRoot(path) {
    var root = siteRoot();
    return root === '/' ? path : root.replace(/\/$/, '') + path;
  }

  /**
   * Language of a path, read from its prefix.
   *
   * The URL is the only trustworthy source here: pjax swaps page content
   * without re-rendering <head>, so anything baked into the markup at build
   * time keeps describing whichever page was loaded first in the tab.
   */
  function languageOf(path) {
    var segments = path.split('/');
    if (segments.length > 1 && LANGS.indexOf(segments[1]) !== -1) return segments[1];
    return DEFAULT_LANG;
  }

  /**
   * Counterpart of `path` in `lang`. Mirrors the `i18n_path` helper: swaps the
   * language prefix and adds/removes the `-en` slug suffix that English post
   * files carry, so /2026/09/25/foo/ ↔ /en/2026/09/25/foo-en/.
   */
  function translatePath(path, lang) {
    var hasIndex = /\/index\.html$/.test(path);
    var work = hasIndex ? path.replace(/index\.html$/, '') : path;
    if (work === '') work = '/';

    var currentLang = languageOf(work);
    if (currentLang !== DEFAULT_LANG) {
      work = work.slice(currentLang.length + 1) || '/';
      if (work.charAt(0) !== '/') work = '/' + work;
    }

    var isPost = /^\/?\d{4}\/\d{2}\/\d{2}\//.test(work);
    var target;
    if (lang === DEFAULT_LANG) {
      target = isPost ? work.replace(/-en(\/?)$/, '$1') : work;
    } else if (isPost) {
      target = '/' + lang + (/-en\/?$/.test(work) ? work : work.replace(/(\/?)$/, '-en$1'));
    } else {
      target = '/' + lang + work;
    }

    if (hasIndex) target = target.replace(/\/$/, '') + '/index.html';
    return addRoot(target);
  }

  /**
   * Rewrite the header links for the page we are actually on.
   *
   * The header sits outside every container pjax swaps, and pjax intercepts all
   * in-site link clicks, so these links keep the URLs baked into the first page
   * loaded in the tab. Without this, picking a language on /archives/ navigates
   * to the language version of whatever page started the session.
   */
  function refreshHeaderLinks() {
    var path = stripRoot(window.location.pathname);
    var current = languageOf(path);

    var options = document.querySelectorAll('.lang-dropdown a[data-lang]');
    var label = document.querySelector('.lang-current');
    for (var i = 0; i < options.length; i++) {
      var lang = options[i].getAttribute('data-lang');
      options[i].setAttribute('href', translatePath(path, lang));
      options[i].classList.toggle('active', lang === current);
      if (label && lang === current) {
        label.textContent = options[i].textContent.replace(/^\s+|\s+$/g, '');
      }
    }

    // The language dropdown lives inside a `.menu-item` itself, so it has to be
    // excluded here: prefixing its links with the current language would undo
    // the per-language URLs set just above.
    var menuLinks = document.querySelectorAll('.site-nav .menu-item:not(.menu-item-languages) a[href]');
    for (var j = 0; j < menuLinks.length; j++) {
      var href = menuLinks[j].getAttribute('href');
      if (!href || href.charAt(0) !== '/' || href.indexOf('//') === 0) continue;
      var segments = stripRoot(href).split('/');
      if (LANGS.indexOf(segments[1]) !== -1) segments.splice(1, 1);
      var rest = segments.join('/') || '/';
      menuLinks[j].setAttribute('href', addRoot(current === DEFAULT_LANG ? rest : '/' + current + rest));
    }
  }

  function bindSwitcher() {
    var dropdown = document.querySelector('.lang-dropdown');
    if (!dropdown) return;
    dropdown.addEventListener('click', function(e) {
      var target = e.target.closest('a[data-lang]');
      if (!target) return;
      e.preventDefault();
      storeLang(target.getAttribute('data-lang'));
      window.location.href = target.getAttribute('href');
    });
  }

  // --- Auto redirect (only on first visit, never chosen a language) ---
  var path = stripRoot(window.location.pathname);
  var pageLang = languageOf(path);
  var stored = getStoredLang();

  // Always store current page language as visited
  storeLang(pageLang);

  // If user has never chosen a language, detect and redirect
  if (!stored) {
    var browserLang = detectBrowserLang();
    // Only redirect if browser language differs from current page language
    // and we are on the actual homepage (not posts, archives, or other pages)
    if (browserLang !== pageLang && /^\/(index\.html)?$/.test(path)) {
      window.location.href = translatePath('/', browserLang);
    }
  }

  // --- Header language dropdown ---
  document.addEventListener('DOMContentLoaded', function() {
    refreshHeaderLinks();
    bindSwitcher();
  });
  // Keep the header in sync with every pjax navigation.
  window.addEventListener('pjax:success', refreshHeaderLinks);
})();
</script>
