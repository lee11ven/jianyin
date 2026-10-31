(function () {
  'use strict';

  var SETTINGS_KEY = 'signspeak.settings.v1';

  var DEFAULT_SETTINGS = {
    confidence: 0.65,
    depthSoft: 0.17,
    depthHard: 0.67,
    biasSoft: 0.17,
    biasHard: 0.78,
    shakeSensitivity: 0.5,
    tPrimeMs: 100,
  };

  function loadSettings() {
    try {
      var raw = localStorage.getItem(SETTINGS_KEY);
      if (!raw) return Object.assign({}, DEFAULT_SETTINGS);
      return Object.assign({}, DEFAULT_SETTINGS, JSON.parse(raw));
    } catch (e) {
      return Object.assign({}, DEFAULT_SETTINGS);
    }
  }

  function saveSettings(data) {
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(data));
  }

  function formatVal(key, n) {
    if (key === 'tPrimeMs') return Math.round(n) + ' ms';
    if (key === 'shakeSensitivity') return Number(n).toFixed(2);
    return Number(n).toFixed(2);
  }

  /* —— Settings page —— */
  function initSettings() {
    var form = document.getElementById('settings-form');
    if (!form) return;

    var data = loadSettings();
    var inputs = form.querySelectorAll('[data-setting]');

    inputs.forEach(function (input) {
      var key = input.getAttribute('data-setting');
      if (data[key] != null) input.value = data[key];
      syncValueLabel(input);
      input.addEventListener('input', function () {
        syncValueLabel(input);
        data[key] = Number(input.value);
        saveSettings(data);
      });
    });

    var resetBtn = document.getElementById('settings-reset');
    if (resetBtn) {
      resetBtn.addEventListener('click', function () {
        data = Object.assign({}, DEFAULT_SETTINGS);
        saveSettings(data);
        inputs.forEach(function (input) {
          var key = input.getAttribute('data-setting');
          input.value = data[key];
          syncValueLabel(input);
        });
      });
    }
  }

  function syncValueLabel(input) {
    var key = input.getAttribute('data-setting');
    var label = document.querySelector('[data-value-for="' + key + '"]');
    if (label) label.textContent = formatVal(key, input.value);
  }

  /* —— Home: captions + camera + status —— */
  /* Sense lane: offline | idle(就绪) | recognizing | translating
     Voice lane: idle | speaking — parallel, does not block sense
     Home lifecycle: open rear cam + WS on enter; teardown on leave (see architecture.md) */
  var SENSE_STATES = {
    offline: { label: '掉线', hint: '连接已断开，正在重试…', hintTone: 'muted' },
    idle: { label: '就绪', hint: '请正对镜头，露出上半身', hintTone: '' },
    recognizing: { label: '识别中', hint: '正在捕捉手语…', hintTone: '' },
    translating: { label: '转译中', hint: '正在生成语音文案…', hintTone: '' },
  };

  var homeSession = {
    stream: null,
    wsSimConnected: false,
  };

  var VOICE_STATES = {
    idle: { label: '语音闲置' },
    speaking: { label: '语音中' },
  };

  var homeRuntime = {
    sense: 'idle',
    voice: 'idle',
    voiceTimer: 0,
  };

  function renderRuntimeStatus() {
    var senseEl = document.getElementById('runtime-status-sense');
    var senseMeta = SENSE_STATES[homeRuntime.sense];

    /* Topbar only shows sense lane; voice lane stays parallel but not displayed */
    if (senseEl && senseMeta) {
      senseEl.setAttribute('data-status', homeRuntime.sense);
      var senseLabel = senseEl.querySelector('.runtime-status__label');
      if (senseLabel) senseLabel.textContent = senseMeta.label;
    }

    var hint = document.getElementById('camera-hint');
    if (hint && senseMeta) {
      hint.textContent = senseMeta.hint;
      if (senseMeta.hintTone) {
        hint.setAttribute('data-tone', senseMeta.hintTone);
      } else {
        hint.removeAttribute('data-tone');
      }
      hint.classList.remove('is-hidden');
    }

    syncViewpointFrame(homeRuntime.sense);
  }

  function setSenseStatus(key) {
    if (!SENSE_STATES[key]) return;
    homeRuntime.sense = key;
    renderRuntimeStatus();
  }

  function setVoiceStatus(key) {
    if (!VOICE_STATES[key]) return;
    homeRuntime.voice = key;
    renderRuntimeStatus();
  }

  function startVoiceSpeaking(durationMs) {
    if (homeRuntime.voiceTimer) {
      window.clearTimeout(homeRuntime.voiceTimer);
      homeRuntime.voiceTimer = 0;
    }
    setVoiceStatus('speaking');
    homeRuntime.voiceTimer = window.setTimeout(function () {
      homeRuntime.voiceTimer = 0;
      setVoiceStatus('idle');
    }, durationMs);
  }

  function initRuntimeStatus() {
    if (!document.getElementById('runtime-status-sense')) return;

    setSenseStatus('idle');
    setVoiceStatus('idle');

    /* Occasional offline blip — only when sense is idle; voice lane untouched */
    var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    window.setInterval(function () {
      if (homeRuntime.sense !== 'idle') return;
      setSenseStatus('offline');
      window.setTimeout(function () {
        if (homeRuntime.sense === 'offline') setSenseStatus('idle');
      }, reduceMotion ? 500 : 1100);
    }, reduceMotion ? 12000 : 18000);
  }

  function syncViewpointFrame(statusKey) {
    var frame = document.querySelector('.vp-frame');
    if (!frame) return;

    var vp = statusKey === 'offline' ? 'red' : 'green';
    var caption =
      statusKey === 'offline' ? '机位矫正 · 连接中断' : '机位矫正 · 头肩双手入框';

    frame.setAttribute('data-vp', vp);
    var cap = frame.querySelector('.vp-frame__caption');
    if (cap) cap.textContent = caption;
  }

  function initCaptions() {
    var el = document.getElementById('caption-stream');
    if (!el) return;

    var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    /* No mock caption stream — wait for real recognition downlink. */
    el.innerHTML = reduceMotion
      ? ''
      : '<span class="cursor" aria-hidden="true"></span>';
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/\n/g, '<br>');
  }

  function initCameraNoise() {
    var canvas = document.getElementById('camera-noise');
    if (!canvas) return;

    var ctx = canvas.getContext('2d', { alpha: true });
    if (!ctx) return;

    var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var w = canvas.width;
    var h = canvas.height;
    var imageData = ctx.createImageData(w, h);
    var data = imageData.data;
    var raf = 0;
    var last = 0;

    function paint() {
      for (var i = 0; i < data.length; i += 4) {
        var n = (Math.random() * 255) | 0;
        data[i] = n;
        data[i + 1] = n;
        data[i + 2] = n;
        data[i + 3] = n > 200 ? 90 : n > 120 ? 40 : 18;
      }
      ctx.putImageData(imageData, 0, 0);
    }

    function loop(ts) {
      if (document.querySelector('.camera-home.is-live-camera')) {
        raf = window.requestAnimationFrame(loop);
        return;
      }
      if (!last || ts - last > (reduceMotion ? 120 : 50)) {
        paint();
        last = ts;
      }
      raf = window.requestAnimationFrame(loop);
    }

    paint();
    if (!reduceMotion) {
      raf = window.requestAnimationFrame(loop);
    } else {
      /* static grain still visible */
      paint();
    }

    window.addEventListener(
      'pagehide',
      function () {
        if (raf) window.cancelAnimationFrame(raf);
      },
      { once: true }
    );
  }

  function teardownHomeSession() {
    var video = document.getElementById('camera-preview');
    if (homeSession.stream) {
      homeSession.stream.getTracks().forEach(function (t) {
        t.stop();
      });
      homeSession.stream = null;
    }
    if (video) {
      video.srcObject = null;
      video.classList.remove('is-live');
    }
    var home = document.querySelector('.camera-home');
    if (home) home.classList.remove('is-live-camera');
    var fallback = document.querySelector('.camera-preview-fallback');
    if (fallback) fallback.hidden = false;
    homeSession.wsSimConnected = false;
    setSenseStatus('offline');
  }

  function initCamera() {
    var video = document.getElementById('camera-preview');
    var home = document.querySelector('.camera-home');
    if (!home) return;

    /* Prototype: entering home ≈ connect WS; status Ready when open */
    homeSession.wsSimConnected = true;
    setSenseStatus('idle');

    if (!video || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      initCameraNoise();
      return;
    }

    initCameraNoise();

    /* Default rear camera (environment); fallback to any video if unavailable */
    navigator.mediaDevices
      .getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false })
      .catch(function () {
        return navigator.mediaDevices.getUserMedia({ video: true, audio: false });
      })
      .then(function (stream) {
        homeSession.stream = stream;
        video.srcObject = stream;
        return video.play();
      })
      .then(function () {
        video.classList.add('is-live');
        home.classList.add('is-live-camera');
        var fallback = document.querySelector('.camera-preview-fallback');
        if (fallback) fallback.hidden = true;
        if (homeSession.wsSimConnected) setSenseStatus('idle');
      })
      .catch(function () {
        /* keep fallback + noise — prototype must not block */
      });

    /*
     * Leave home / close tab → release camera + mark WS down.
     * Screen off / background while still on home: do NOT teardown
     * (visibilitychange hidden alone must not stop session).
     */
    window.addEventListener('pagehide', teardownHomeSession);
    document.querySelectorAll('.camera-topbar a[href]').forEach(function (link) {
      link.addEventListener('click', function () {
        teardownHomeSession();
      });
    });
  }

  /* —— History: calendar multi-select export —— */
  function initHistoryExport() {
    var openBtn = document.getElementById('history-export');
    var dialog = document.getElementById('cal-dialog');
    var grid = document.getElementById('cal-grid');
    var title = document.getElementById('cal-title');
    var confirmBtn = document.getElementById('cal-confirm');
    if (!openBtn || !dialog || !grid || !title || !confirmBtn) return;

    var byDay = {};
    document.querySelectorAll('.day-group[data-day]').forEach(function (group) {
      var day = group.getAttribute('data-day');
      var items = [];
      group.querySelectorAll('.history-card').forEach(function (card) {
        var timeEl = card.querySelector('time');
        var textEl = card.querySelector('p');
        items.push({
          time: timeEl ? timeEl.textContent.trim() : '',
          text: textEl ? textEl.textContent.trim() : '',
        });
      });
      if (day && items.length) {
        byDay[day] = {
          label: group.getAttribute('data-day-label') || day,
          items: items,
        };
      }
    });

    var days = Object.keys(byDay).sort();
    var anchor = days.length ? days[days.length - 1] : '2026-10-25';
    var view = {
      y: Number(anchor.slice(0, 4)),
      m: Number(anchor.slice(5, 7)) - 1,
    };
    var picked = {};

    function pad(n) {
      return n < 10 ? '0' + n : String(n);
    }

    function iso(y, m, d) {
      return y + '-' + pad(m + 1) + '-' + pad(d);
    }

    function pickedList() {
      return Object.keys(picked).filter(function (k) {
        return picked[k];
      }).sort();
    }

    function syncConfirm() {
      var n = pickedList().length;
      confirmBtn.disabled = n === 0;
      confirmBtn.textContent = n > 0 ? '导出（' + n + '）' : '导出';
    }

    function render() {
      title.textContent = view.y + '年' + (view.m + 1) + '月';
      grid.innerHTML = '';
      var first = new Date(view.y, view.m, 1);
      var startPad = (first.getDay() + 6) % 7;
      var count = new Date(view.y, view.m + 1, 0).getDate();
      var i;
      for (i = 0; i < startPad; i += 1) {
        var padCell = document.createElement('span');
        padCell.className = 'cal-day is-out';
        grid.appendChild(padCell);
      }
      for (i = 1; i <= count; i += 1) {
        var key = iso(view.y, view.m, i);
        var has = !!byDay[key];
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'cal-day';
        btn.textContent = String(i);
        btn.setAttribute('data-day', key);
        if (!has) {
          btn.disabled = true;
          btn.classList.add('is-empty');
          btn.setAttribute('aria-label', i + '日，无字幕');
        } else {
          btn.classList.add('is-has');
          if (picked[key]) btn.classList.add('is-picked');
          btn.setAttribute('aria-pressed', picked[key] ? 'true' : 'false');
          btn.setAttribute('aria-label', key + '，有字幕');
        }
        grid.appendChild(btn);
      }
      syncConfirm();
    }

    function openDialog() {
      picked = {};
      dialog.hidden = false;
      render();
    }

    function closeDialog() {
      dialog.hidden = true;
    }

    function exportTxt() {
      var list = pickedList();
      if (!list.length) return;
      var lines = ['见音 · 历史字幕', ''];
      list.forEach(function (day) {
        var rec = byDay[day];
        lines.push(rec.label + ' ' + day);
        rec.items.forEach(function (item) {
          lines.push(item.time);
          lines.push(item.text);
          lines.push('');
        });
      });
      var compact = list.map(function (d) {
        return d.replace(/-/g, '');
      });
      var name =
        compact.length === 1
          ? '见音字幕_' + compact[0] + '.txt'
          : '见音字幕_' + compact[0] + '-' + compact[compact.length - 1] + '.txt';
      var blob = new Blob(['\uFEFF' + lines.join('\n')], {
        type: 'text/plain;charset=utf-8',
      });
      var url = URL.createObjectURL(blob);
      var a = document.createElement('a');
      a.href = url;
      a.download = name;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      closeDialog();
    }

    openBtn.addEventListener('click', openDialog);
    document.getElementById('cal-prev').addEventListener('click', function () {
      view.m -= 1;
      if (view.m < 0) {
        view.m = 11;
        view.y -= 1;
      }
      render();
    });
    document.getElementById('cal-next').addEventListener('click', function () {
      view.m += 1;
      if (view.m > 11) {
        view.m = 0;
        view.y += 1;
      }
      render();
    });
    grid.addEventListener('click', function (e) {
      var btn = e.target.closest('.cal-day');
      if (!btn || btn.disabled) return;
      var key = btn.getAttribute('data-day');
      if (!byDay[key]) return;
      picked[key] = !picked[key];
      render();
    });
    confirmBtn.addEventListener('click', exportTxt);
    dialog.querySelectorAll('[data-cal-close]').forEach(function (el) {
      el.addEventListener('click', closeDialog);
    });
  }

  /* —— Auth forms —— */
  function initAuthForms() {
    document.querySelectorAll('form[data-nav]').forEach(function (form) {
      form.addEventListener('submit', function (e) {
        e.preventDefault();
        var target = form.getAttribute('data-nav') || 'home.html';
        window.location.href = target;
      });
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    initSettings();
    initRuntimeStatus();
    initCaptions();
    initCamera();
    initHistoryExport();
    initAuthForms();
  });
})();
