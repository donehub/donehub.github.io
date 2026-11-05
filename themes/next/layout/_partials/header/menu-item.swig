{% macro render(name, itemName, value) %}

  {%- set itemURL = value.split('||')[0] | trim %}
  {%- if not itemURL.startsWith('http') %}
    {%- set itemURL = itemURL | replace('//', '/') %}
    {%- set itemURL = lang_url(itemURL) %}
  {%- endif %}
  <li class="menu-item menu-item-{{ itemName | replace(' ', '-') }}">

    {%- set menuIcon = '' %}
    {%- if theme.menu_settings.icons %}
      {%- set menuIcon = '<i class="fa fa-fw fa-' + value.split('||')[1] | trim + '"></i>' %}
    {%- endif %}
    {%- set menuText = __('menu.' + name) | replace('menu.', '') %}

    {%- set menuBadge = '' %}
    {%- if theme.menu_settings.badges %}
      {%- set badges = {
        archives  : lang_post_count(current_lang()),
        categories: site.categories.length,
        tags      : site.tags.length
        }
      %}
      {%- for menu, count in badges %}
        {%- if name == menu %}
          {%- set menuBadge = '<span class="badge">' + count + '</span>' %}
        {%- endif %}
      {%- endfor %}
    {%- endif %}

    {{ next_url(itemURL, menuIcon + menuText + menuBadge, {rel: 'section'}) }}

  </li>

{% endmacro %}
