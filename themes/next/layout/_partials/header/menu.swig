{% import 'menu-item.swig' as menu_item with context %}

<nav class="site-nav">
{%- if theme.menu %}
  <ul id="menu" class="menu">
    {%- for name, path in theme.menu %}
      {%- set respath = path %}
      {%- if path == '[object Object]' %}
        {# Main Menu (default menu item for Submenu) #}
        {%- for subname, subpath in path %}
          {%- set itemName = subname | lower %}
          {%- set respath = subpath %}
          {%- if itemName == 'default' %}
            {%- set itemName = name | lower %}
            {{ menu_item.render(name, itemName, respath) }}
          {%- endif %}
        {%- endfor %}
      {% else %}
        {# Main Menu (standard menu items) #}
        {%- set itemName = name | lower %}
        {{- menu_item.render(name, itemName, respath) | trim }}
      {%- endif %}
    {%- endfor %}

    {%- if theme.algolia_search.enable or theme.local_search.enable %}
      <li class="menu-item menu-item-search">
        <a role="button" class="popup-trigger">
          {%- if theme.menu_settings.icons %}<i class="fa fa-search fa-fw"></i>{%- endif %}{{ __('menu.search') }}
        </a>
      </li>
    {%- endif %}

    {%- if theme.language_switcher and languages and languages.length > 1 %}
      <li class="menu-item menu-item-languages">
        <a class="lang-switch-btn" role="button" title="Language">
          <i class="fa fa-language fa-fw"></i>
          <span class="lang-current">中文</span>
          <i class="fa fa-angle-down fa-fw" style="font-size:12px"></i>
        </a>
        <div class="lang-dropdown">
          {% for lang in languages %}
            <a href="{{ lang_home(lang) }}" data-lang="{{ lang }}">{% if lang == 'en' %}English{% else %}中文{% endif %}</a>
          {% endfor %}
        </div>
      </li>
    {%- endif %}
  </ul>
{%- endif %}
</nav>
