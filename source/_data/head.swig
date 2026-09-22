<meta name="page-lang" content="{{ page.lang }}">
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
  var LANGS = ['zh-CN', 'en'];
  var LANG_HOME = { 'zh-CN': '/', 'en': '/en/' };
  var STORAGE_KEY = 'donehub_lang';

  function storeLang(lang) {
    try { localStorage.setItem(STORAGE_KEY, lang); } catch(e) {}
  }

  function getStoredLang() {
    try { return localStorage.getItem(STORAGE_KEY); } catch(e) { return null; }
  }

  function detectBrowserLang() {
    var raw = (navigator.language || navigator.userLanguage || 'zh-CN').toLowerCase();
    if (raw.indexOf('en') === 0) return 'en';
    return 'zh-CN';
  }

  function currentLang() {
    var meta = document.querySelector('meta[name="page-lang"]');
    return (meta && meta.content) || 'zh-CN';
  }

  function currentPathname() {
    return window.location.pathname;
  }

  // --- Auto redirect (only on first visit, never chosen a language) ---
  var stored = getStoredLang();
  var pageLang = currentLang();
  var pathname = currentPathname();

  // Always store current page language as visited
  storeLang(pageLang);

  // If user has never chosen a language, detect and redirect
  if (!stored) {
    var browserLang = detectBrowserLang();
    // Only redirect if browser language differs from current page language
    // and we are on a homepage (not a specific post)
    if (browserLang !== pageLang && /^\/(en\/)?(\d|page|tags|categories|about|$)/.test(pathname)) {
      window.location.href = LANG_HOME[browserLang] || '/';
      return;
    }
  }

  // --- Header language dropdown ---
  document.addEventListener('DOMContentLoaded', function() {
    var current = currentLang();
    var langNames = { 'zh-CN': '中文', 'en': 'English' };

    // Update button text to reflect current page language
    var langCurrent = document.querySelector('.lang-current');
    if (langCurrent && langNames[current]) {
      langCurrent.textContent = langNames[current];
    }

    // Highlight active language option in dropdown
    var options = document.querySelectorAll('.lang-dropdown a');
    for (var i = 0; i < options.length; i++) {
      if (options[i].getAttribute('data-lang') === current) {
        options[i].classList.add('active');
      }
    }

    // Click handler: switch language
    var dropdown = document.querySelector('.lang-dropdown');
    if (!dropdown) return;
    dropdown.addEventListener('click', function(e) {
      var target = e.target.closest('a[data-lang]');
      if (!target) return;
      e.preventDefault();
      var lang = target.getAttribute('data-lang');
      storeLang(lang);
      window.location.href = target.getAttribute('href');
    });
  });
})();
</script>
