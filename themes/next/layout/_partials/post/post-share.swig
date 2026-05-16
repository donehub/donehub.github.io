{%- if theme.social_share.enable %}
<div class="post-share">
  <div class="share-title">{{ theme.social_share.title or '分享到' }}</div>
  <div class="social-share" data-sites="{{ theme.social_share.sites or 'wechat,weibo,qzone,qq' }}"></div>
</div>

<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/social-share.js@1.0.16/dist/css/share.min.css">
<script src="https://cdn.jsdelivr.net/npm/social-share.js@1.0.16/dist/js/social-share.min.js"></script>

<style>
.post-share {
  margin: 20px 0;
  padding: 15px 0;
  border-top: 1px solid #eee;
  border-bottom: 1px solid #eee;
}
.post-share .share-title {
  font-size: 14px;
  color: #999;
  margin-bottom: 10px;
}
.post-share .social-share {
  text-align: center;
}
.post-share .social-share a {
  margin: 0 8px;
}
/* 微信二维码样式优化 */
.social-share .wechat-qrcode {
  border: 1px solid #eee;
  border-radius: 4px;
  box-shadow: 0 2px 10px rgba(0,0,0,0.1);
}
.social-share .wechat-qrcode h4 {
  color: #333;
  font-weight: normal;
}
</style>
{%- endif %}