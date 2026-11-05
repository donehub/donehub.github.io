{%- set valine_uri = theme.vendors.valine or '//unpkg.com/valine/dist/Valine.min.js' %}

{#- Valine only ships en / zh-cn UI strings; follow the page language #}
{%- if theme.valine.language %}
  {%- set valine_lang = theme.valine.language %}
{%- elif current_lang() === 'en' %}
  {%- set valine_lang = 'en' %}
{%- else %}
  {%- set valine_lang = 'zh-cn' %}
{%- endif %}

<script>
NexT.utils.loadComments(document.querySelector('#valine-comments'), () => {
  NexT.utils.getScript('{{ valine_uri }}', () => {
    var GUEST = ['nick', 'mail', 'link'];
    var guest = '{{ theme.valine.guest_info }}';
    guest = guest.split(',').filter(item => {
      return GUEST.includes(item);
    });
    new Valine({
      el         : '#valine-comments',
      verify     : {{ theme.valine.verify }},
      notify     : {{ theme.valine.notify }},
      appId      : '{{ theme.valine.appid }}',
      appKey     : '{{ theme.valine.appkey }}',
      placeholder: {{ theme.valine.placeholder | json }},
      avatar     : '{{ theme.valine.avatar }}',
      meta       : guest,
      pageSize   : '{{ theme.valine.pageSize }}' || 10,
      visitor    : {{ theme.valine.visitor }},
      lang       : '{{ valine_lang }}',
      path       : location.pathname,
      recordIP   : {{ theme.valine.recordIP }},
      serverURLs : '{{ theme.valine.serverURLs }}'
    });
  }, window.Valine);
});
</script>
