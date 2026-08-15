{%- if theme.social_share.enable %}
<div class="post-share">
  <!-- 自定义分享按钮 -->
  <div class="share-title">{{ theme.social_share.title or '分享到' }}</div>
  <div class="custom-share-btns">
    <button class="cs-btn cs-btn-qrcode" onclick="openShareModal()">
      <span class="cs-icon">📱</span>
      <span class="cs-label">二维码</span>
    </button>
    <button class="cs-btn cs-btn-copy" id="csCopyBtn" onclick="copyPageUrl()">
      <span class="cs-icon">🔗</span>
      <span class="cs-label" id="csCopyLabel">复制链接</span>
    </button>
  </div>

  <!-- 二维码弹窗 -->
  <div class="cs-modal-overlay" id="csModalOverlay" onclick="closeShareModal(event)">
    <div class="cs-modal" onclick="event.stopPropagation()">
      <button class="cs-modal-close" onclick="closeShareModal()">&times;</button>
      <div class="cs-modal-title" id="csModalTitle">扫描二维码分享</div>
      <div class="cs-modal-hint" id="csModalHint"></div>
      <div class="cs-qrcode" id="csQrcode"></div>
      <button class="cs-copy-img-btn" id="csCopyImgBtn" onclick="copyQrcodeImage()">
        <span id="csCopyImgLabel">📋 复制为图片</span>
      </button>
      <div class="cs-modal-url" id="csModalUrl"></div>
    </div>
  </div>

  <!-- 原有 social-share.js -->
  <div class="social-share" data-sites="{{ theme.social_share.sites or 'wechat,weibo,qzone,qq' }}"></div>
</div>

<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/social-share.js@1.0.16/dist/css/share.min.css">
<script src="https://cdn.jsdelivr.net/npm/social-share.js@1.0.16/dist/js/social-share.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js"></script>

<style>
/* 自定义分享按钮 */
.custom-share-btns {
  display: flex;
  justify-content: center;
  gap: 12px;
  margin-bottom: 16px;
  flex-wrap: wrap;
}
.cs-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 18px;
  border: 1px solid #e0e0e0;
  border-radius: 20px;
  background: #fff;
  cursor: pointer;
  font-size: 14px;
  color: #555;
  transition: all 0.2s ease;
  outline: none;
}
.cs-btn:hover {
  border-color: #2563eb;
  color: #2563eb;
  box-shadow: 0 2px 8px rgba(37, 99, 235, 0.15);
}
.cs-btn:active { transform: scale(0.96); }
.cs-btn-qrcode:hover { border-color: #2563eb; color: #2563eb; }
.cs-btn-copy:hover { border-color: #f59e0b; color: #f59e0b; box-shadow: 0 2px 8px rgba(245, 158, 11, 0.15); }
.cs-icon { font-size: 16px; line-height: 1; }
.cs-label { white-space: nowrap; }

/* 弹窗 */
.cs-modal-overlay {
  display: none;
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  z-index: 9999;
  justify-content: center;
  align-items: center;
  backdrop-filter: blur(2px);
}
.cs-modal-overlay.active { display: flex; }
.cs-modal {
  background: #fff;
  border-radius: 16px;
  padding: 28px 32px 24px;
  max-width: 340px;
  width: 90%;
  text-align: center;
  position: relative;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.2);
  animation: csFadeIn 0.2s ease;
}
@keyframes csFadeIn {
  from { opacity: 0; transform: scale(0.92); }
  to { opacity: 1; transform: scale(1); }
}
.cs-modal-close {
  position: absolute;
  top: 12px;
  right: 16px;
  border: none;
  background: none;
  font-size: 22px;
  color: #999;
  cursor: pointer;
  line-height: 1;
  padding: 4px 8px;
}
.cs-modal-close:hover { color: #333; }
.cs-modal-title {
  font-size: 17px;
  font-weight: 600;
  color: #1a1a2e;
  margin-bottom: 6px;
}
.cs-modal-hint {
  font-size: 13px;
  color: #888;
  margin-bottom: 18px;
  line-height: 1.5;
}
.cs-qrcode {
  display: inline-block;
  padding: 12px;
  border: 1px solid #eee;
  border-radius: 8px;
  margin-bottom: 14px;
}
.cs-qrcode img { display: block; }
.cs-copy-img-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 6px 16px;
  margin-bottom: 14px;
  border: 1px solid #d0d5dd;
  border-radius: 8px;
  background: #fff;
  cursor: pointer;
  font-size: 13px;
  color: #555;
  transition: all 0.2s;
}
.cs-copy-img-btn:hover {
  border-color: #2563eb;
  color: #2563eb;
  background: #f0f4ff;
}
.cs-copy-img-btn:active { transform: scale(0.96); }
.cs-modal-url {
  font-size: 12px;
  color: #aaa;
  word-break: break-all;
  line-height: 1.5;
  max-width: 100%;
}

/* 暗色主题适配 */
@media (prefers-color-scheme: dark) {
  .cs-btn {
    background: #1e293b;
    border-color: #334155;
    color: #cbd5e1;
  }
  .cs-btn:hover {
    border-color: #60a5fa;
    color: #60a5fa;
  }
  .cs-btn-copy:hover { border-color: #fbbf24; color: #fbbf24; }
  .cs-modal {
    background: #1e293b;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
  }
  .cs-modal-title { color: #e2e8f0; }
  .cs-modal-hint { color: #94a3b8; }
  .cs-qrcode { border-color: #334155; }
  .cs-modal-close { color: #64748b; }
  .cs-modal-close:hover { color: #e2e8f0; }
  .cs-modal-url { color: #64748b; }
  .cs-copy-img-btn {
    background: #0f172a;
    border-color: #475569;
    color: #cbd5e1;
  }
  .cs-copy-img-btn:hover {
    border-color: #60a5fa;
    color: #60a5fa;
    background: #1e293b;
  }
}

/* 移动端 */
@media (max-width: 500px) {
  .custom-share-btns { gap: 8px; }
  .cs-btn { padding: 7px 14px; font-size: 13px; }
  .cs-modal { padding: 22px 20px 18px; }
}
</style>

<script>
(function() {
  var qrcodeInstance = null;

  window.openShareModal = function() {
    var overlay = document.getElementById('csModalOverlay');
    var title = document.getElementById('csModalTitle');
    var hint = document.getElementById('csModalHint');
    var qrcodeEl = document.getElementById('csQrcode');
    var urlEl = document.getElementById('csModalUrl');
    var pageUrl = window.location.href;

    title.textContent = '扫描二维码分享';
    hint.textContent = '用手机扫码即可在手机上打开本篇文章';
    urlEl.textContent = pageUrl;

    // 清除旧二维码
    qrcodeEl.innerHTML = '';

    // 生成新二维码
    if (typeof QRCode !== 'undefined') {
      qrcodeInstance = new QRCode(qrcodeEl, {
        text: pageUrl,
        width: 200,
        height: 200,
        colorDark: '#1a1a2e',
        colorLight: '#ffffff',
        correctLevel: QRCode.CorrectLevel.M
      });
    }

    overlay.classList.add('active');
    document.body.style.overflow = 'hidden';
  };

  window.closeShareModal = function(e) {
    if (e && e.target !== e.currentTarget && e.type === 'click') return;
    var overlay = document.getElementById('csModalOverlay');
    overlay.classList.remove('active');
    document.body.style.overflow = '';
  };

  // ESC 关闭
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
      var overlay = document.getElementById('csModalOverlay');
      if (overlay.classList.contains('active')) {
        overlay.classList.remove('active');
        document.body.style.overflow = '';
      }
    }
  });

  window.copyPageUrl = function() {
    var btn = document.getElementById('csCopyBtn');
    var label = document.getElementById('csCopyLabel');
    var pageUrl = window.location.href;

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(pageUrl).then(function() {
        showCopied(btn, label);
      }).catch(function() {
        fallbackCopy(pageUrl, btn, label);
      });
    } else {
      fallbackCopy(pageUrl, btn, label);
    }
  };

  function fallbackCopy(text, btn, label) {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;left:-9999px';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); showCopied(btn, label); }
    catch(e) { label.textContent = '复制失败'; }
    document.body.removeChild(ta);
  }

  function showCopied(btn, label) {
    label.textContent = '✅ 已复制';
    btn.classList.add('cs-copied');
    setTimeout(function() {
      label.textContent = '复制链接';
      btn.classList.remove('cs-copied');
    }, 2000);
  }

  window.copyQrcodeImage = function() {
    var btn = document.getElementById('csCopyImgBtn');
    var label = document.getElementById('csCopyImgLabel');
    var qrcodeEl = document.getElementById('csQrcode');
    var canvas = qrcodeEl.querySelector('canvas');

    if (!canvas) {
      // qrcodejs 可能用 img 标签渲染，尝试从 img 获取
      var img = qrcodeEl.querySelector('img');
      if (img) {
        // 创建 canvas 从 img 绘制
        canvas = document.createElement('canvas');
        canvas.width = img.width || 200;
        canvas.height = img.height || 200;
        var ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0);
      }
    }

    if (!canvas) { label.textContent = '❌ 生成失败'; return; }

    canvas.toBlob(function(blob) {
      if (!blob) { label.textContent = ' 生成失败'; return; }

      if (navigator.clipboard && navigator.clipboard.write && window.ClipboardItem) {
        var item = new ClipboardItem({ 'image/png': blob });
        navigator.clipboard.write([item]).then(function() {
          label.textContent = '✅ 已复制';
          setTimeout(function() { label.textContent = ' 复制为图片'; }, 2000);
        }).catch(function() {
          label.textContent = '❌ 复制失败';
          setTimeout(function() { label.textContent = '📋 复制为图片'; }, 2000);
        });
      } else {
        // fallback: 下载图片
        var url = canvas.toDataURL('image/png');
        var a = document.createElement('a');
        a.href = url;
        a.download = 'qrcode.png';
        a.click();
        label.textContent = '️ 已下载';
        setTimeout(function() { label.textContent = '📋 复制为图片'; }, 2000);
      }
    }, 'image/png');
  };
})();
</script>
{%- endif %}
