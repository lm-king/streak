
(function () {
  var $ = function (id) { return document.getElementById(id); };

  var now = new Date();
  var TODAY = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  var WD = ['一', '二', '三', '四', '五', '六', '日'];
  var GRACE = 6, CARDS = 6, SIZE = 114, W = 390;

  function key(d) {
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }
  function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); }
  function iso(d) { return d.getDay() === 0 ? 7 : d.getDay(); }
  function back(n) { return addDays(TODAY, -n); }
  var TODAY_KEY = key(TODAY);

  function hhmm(hh, mm) {
    return String(hh).padStart(2, '0') + ':' + String(mm).padStart(2, '0');
  }
  // 模拟「那一天几点几分打的卡」。用天数当种子，保证每次刷新看到的时间一致。
  function stamp(daysAgo, baseHour, span) {
    return { hh: baseHour + (daysAgo * 7) % span, mm: (daysAgo * 17) % 60, mk: 0 };
  }
  function nowRec() {
    var n = new Date();
    return { hh: n.getHours(), mm: n.getMinutes(), mk: 0 };
  }

  /* ================= 数据 ================= */
  var habits = [];

  (function seed() {
    // 早起：350 天连到今天昨天，今天未打
    var early = { id: 'early', name: '早起', glyph: '早', checked: {}, notes: {}, cards: CARDS };
    for (var i = 1; i <= 350; i++) early.checked[key(back(i))] = stamp(i, 5, 4);
    var s = 20261109;
    function rnd() { s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648; }
    for (var j = 355; j <= 470; j++) { if (rnd() < 0.55) early.checked[key(back(j))] = stamp(j, 5, 4); }
    early.notes[key(back(1))] = '早上跑步 5km';
    early.notes[key(back(3))] = '状态不错，继续。';

    // 阅读：连续 12 天，断了 2 天
    var read = { id: 'read', name: '阅读', glyph: '读', checked: {}, notes: {}, cards: CARDS };
    for (var a = 3; a <= 14; a++) read.checked[key(back(a))] = stamp(a, 20, 4);
    for (var b = 20; b <= 26; b++) read.checked[key(back(b))] = stamp(b, 20, 4);
    read.notes[key(back(5))] = '《人类简史》第 4 章';

    // 健身：断了 9 天，已清零
    var fit = { id: 'fit', name: '健身', glyph: '健', checked: {}, notes: {}, cards: CARDS };
    for (var c = 10; c <= 15; c++) fit.checked[key(back(c))] = stamp(c, 18, 3);

    habits.push(early, read, fit);
  })();

  /* ================= 连续天数 / 补签 ================= */
  function compute(h) {
    function has(d) { return !!h.checked[key(d)]; }
    var cur = TODAY;
    if (!has(cur)) cur = addDays(cur, -1);
    var n = 0;
    while (has(cur)) { n++; cur = addDays(cur, -1); }
    if (n > 0) return { days: n, gap: 0, makable: false, broken: false, restored: n };

    var p = addDays(TODAY, -1), gap = 0;
    while (gap <= GRACE && !has(p)) { gap++; p = addDays(p, -1); }
    if (gap > GRACE) return { days: 0, gap: gap, makable: false, broken: true, restored: 0 };

    var prev = 0;
    while (has(p)) { prev++; p = addDays(p, -1); }
    if (prev === 0) return { days: 0, gap: gap, makable: false, broken: true, restored: 0 };

    return { days: prev, gap: gap, makable: h.cards >= gap, broken: false, restored: prev + gap };
  }

  function doMakeup(h) {
    var info = compute(h);
    if (!info.makable || !info.gap) return false;
    var n = new Date();
    var dm = (n.getMonth() + 1) + '月' + n.getDate() + '日 ';
    for (var i = 1; i <= info.gap; i++) {
      h.checked[key(back(i))] = { hh: n.getHours(), mm: n.getMinutes(), mk: 1, dm: dm };
    }
    h.cards = Math.max(0, h.cards - info.gap);
    persist();
    return true;
  }

  // 历史上最长的一段连续打卡。按日期 key 排序后走一遍即可。
  function longestStreak(h) {
    var ks = Object.keys(h.checked).sort();
    if (!ks.length) return 0;
    function toDate(k) { var p = k.split('-'); return new Date(+p[0], p[1] - 1, +p[2]); }
    var best = 1, run = 1;
    for (var i = 1; i < ks.length; i++) {
      if (toDate(ks[i]).getTime() - toDate(ks[i - 1]).getTime() === 86400000) {
        run++;
        if (run > best) best = run;
      } else run = 1;
    }
    return best;
  }

  /* ================= 超大滚动数字 ================= */
  function ty(h, pos) { return 'translateY(' + (-(pos + 10) * SIZE) + 'px)'; }
  function digitAt(pos) { return ((pos % 10) + 10) % 10; }

  function buildNumber(h, value, spin) {
    var el = h.numEl;
    el.innerHTML = '';
    el.style.setProperty('--n', SIZE + 'px');
    h.cols = [];
    var ds = String(value).split('');
    for (var i = 0; i < ds.length; i++) {
      var d = Number(ds[i]);
      var col = document.createElement('div'); col.className = 'col';
      var strip = document.createElement('div'); strip.className = 'strip';
      for (var k = -10; k <= 20; k++) {
        var c = document.createElement('div'); c.className = 'cell';
        c.textContent = String(((k % 10) + 10) % 10);
        strip.appendChild(c);
      }
      col.appendChild(strip); el.appendChild(col);
      h.cols.push({ strip: strip, pos: spin ? d - 10 : d, digit: d, delay: 70 * i });
    }
    h.cols.forEach(function (c) { c.strip.style.transition = 'none'; c.strip.style.transform = ty(h, c.pos); });
    if (spin) {
      requestAnimationFrame(function () {
        requestAnimationFrame(function () {
          h.cols.forEach(function (c) {
            c.strip.style.transition = 'transform 560ms cubic-bezier(.215,.61,.355,1) ' + c.delay + 'ms';
            c.pos = c.digit;
            c.strip.style.transform = ty(h, c.pos);
          });
        });
      });
    }
  }

  function snap(h, c, digit) {
    // 滚动结束后把位置归一到 0..9，避免连续加很多天后位置跑出预渲染的格数
    c.pos = digit;
    c.strip.style.transition = 'none';
    c.strip.style.transform = ty(h, c.pos);
  }

  function setNumber(h, value) {
    var ds = String(value).split('');
    if (!h.cols || ds.length !== h.cols.length) { buildNumber(h, value, false); return; }
    for (var i = 0; i < ds.length; i++) {
      var c = h.cols[i], d = Number(ds[i]);
      var base = Math.round(c.pos);
      var delta = ((d - digitAt(base)) + 10) % 10;
      if (delta === 0) continue;
      var target = delta <= 5 ? base + delta : base - (10 - delta);
      c.pos = target;
      c.strip.style.transition = 'transform 560ms cubic-bezier(.215,.61,.355,1)';
      c.strip.style.transform = ty(h, c.pos);
      clearTimeout(c.timer);
      c.timer = setTimeout(function (col, dg) {
        return function () { snap(h, col, dg); };
      }(c, d), 640);
    }
  }

  /* ================= 日历 ================= */
  var firstMonth = new Date(TODAY.getFullYear(), TODAY.getMonth() - 18, 1);
  var lastMonth = new Date(TODAY.getFullYear(), TODAY.getMonth() + 8, 1);
  var lastDay = new Date(lastMonth.getFullYear(), lastMonth.getMonth() + 1, 0);

  var ROWS = [];
  (function buildRows() {
    var cursor = addDays(firstMonth, -(iso(firstMonth) - 1));
    while (cursor <= lastDay) {
      var days = [];
      for (var i = 0; i < 7; i++) days.push(addDays(cursor, i));
      var label = null;
      for (var j = 0; j < 7; j++) {
        if (days[j].getDate() === 1) { label = new Date(days[j].getFullYear(), days[j].getMonth(), 1); break; }
      }
      ROWS.push({ days: days, label: label });
      cursor = addDays(cursor, 7);
    }
  })();

  var monthOffset = (function () {
    var hgt = 0;
    for (var i = 0; i < ROWS.length; i++) {
      var lb = ROWS[i].label;
      if (lb && lb.getMonth() === TODAY.getMonth() && lb.getFullYear() === TODAY.getFullYear()) break;
      hgt += (lb ? 46 : 0) + 54;
    }
    return hgt;
  })();

  function buildCalendar(h, calEl) {
    h.cells = [];
    var frag = document.createDocumentFragment();
    ROWS.forEach(function (row) {
      if (row.label) {
        var l = document.createElement('div'); l.className = 'rowLabel';
        l.textContent = row.label.getFullYear() + '年 ' + (row.label.getMonth() + 1) + '月';
        frag.appendChild(l);
      }
      var r = document.createElement('div'); r.className = 'row';
      var ref = row.label || row.days[0];
      row.days.forEach(function (d) {
        var wrap = document.createElement('div'); wrap.className = 'day';
        var dd = document.createElement('div'); dd.className = 'dd';
        var num = document.createElement('div'); num.className = 'dnum'; num.textContent = d.getDate();
        var sub = document.createElement('div'); sub.className = 'dsub';
        var isToday = d.getTime() === TODAY.getTime();
        var inMonth = d.getMonth() === ref.getMonth() && d.getFullYear() === ref.getFullYear();
        if (isToday) {
          dd.classList.add('today');
          sub.textContent = '今天';
          h.todayCell = dd;
        } else {
          var dot = document.createElement('i'); dot.className = 'dot';
          sub.appendChild(dot);
        }
        // 每一天都能点：未来的日子也会弹窗，只是内容显示「还没到」
        wrap.classList.add('tap');
        wrap.addEventListener('click', function () { onDayTap(h, d); });
        dd.appendChild(num); dd.appendChild(sub); wrap.appendChild(dd);
        r.appendChild(wrap);
        h.cells.push({ num: num, sub: sub, dot: sub.firstChild, d: d, inMonth: inMonth, isToday: isToday });
      });
      frag.appendChild(r);
    });
    calEl.appendChild(frag);
    calEl.scrollTop = monthOffset;
  }

  function paintCells(h) {
    for (var i = 0; i < h.cells.length; i++) {
      var c = h.cells[i];
      if (c.isToday) continue;
      var ck = !!h.checked[key(c.d)];
      if (!c.inMonth) {
        c.num.style.color = '#ededed';
        c.num.style.fontWeight = '500';
      } else if (ck) {
        c.num.style.color = '#111';
        c.num.style.fontWeight = '700';
      } else {
        c.num.style.color = '#e0e0e0';
        c.num.style.fontWeight = '500';
      }
      if (c.dot) {
        var noted = c.inMonth && !!h.notes[key(c.d)];
        c.dot.style.display = noted ? 'block' : 'none';
        c.dot.style.background = ck ? '#b0b0b0' : '#dcdcdc';
      }
    }
  }

  /* ================= 页面构建 ================= */
  var PAGER = $('pager');
  var idx = 0;

  /* ================= 本地持久化（localStorage） ================= */
  var LS_KEY = 'streak.data.v1';

  function persist() {
    try {
      localStorage.setItem(LS_KEY, JSON.stringify({
        idx: idx,
        habits: habits.map(function (h) {
          return { id: h.id, name: h.name, glyph: h.glyph, checked: h.checked, notes: h.notes, cards: h.cards };
        })
      }));
    } catch (e) { /* 隐身模式等 localStorage 不可用的场景：静默降级为内存模式 */ }
  }

  function restore() {
    try {
      var raw = localStorage.getItem(LS_KEY);
      if (!raw) return false;
      var d = JSON.parse(raw);
      if (!d || !Array.isArray(d.habits) || !d.habits.length) return false;
      habits = d.habits.map(function (h) {
        var name = String(h.name || '项目');
        return {
          id: String(h.id || 'h' + Math.random().toString(36).slice(2)),
          name: name,
          glyph: String(h.glyph || name.substring(0, 1)),
          checked: h.checked || {},
          notes: h.notes || {},
          cards: typeof h.cards === 'number' ? h.cards : CARDS
        };
      });
      idx = Math.min(Math.max(0, d.idx | 0), habits.length - 1);
      return true;
    } catch (e) { return false; }
  }

  // 有历史数据就恢复；第一次访问则把演示数据写进去
  if (!restore()) persist();

  var CHECK_SVG = '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#111" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"></path></svg>';
  var CHEV = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9a9a9a" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"></path></svg>';
  var PENCIL = '<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#8e8e8e" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"></path><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4z"></path></svg>';

  function createPage(h) {
    var page = document.createElement('div'); page.className = 'page';

    var bar = document.createElement('div'); bar.className = 'topbar';

    var pname = document.createElement('button'); pname.className = 'pname';
    var pnRow = document.createElement('span'); pnRow.className = 'pnRow';
    var pnText = document.createElement('span'); pnText.className = 'pnText';
    pnText.textContent = h.name;
    var chev = document.createElement('span'); chev.className = 'chev'; chev.innerHTML = CHEV;
    pnRow.appendChild(pnText); pnRow.appendChild(chev);
    var dots = document.createElement('span'); dots.className = 'dots';
    pname.appendChild(pnRow); pname.appendChild(dots);
    pname.addEventListener('click', openSheet);

    var pen = document.createElement('button'); pen.className = 'pen'; pen.innerHTML = PENCIL;
    pen.setAttribute('aria-label', '记事');
    pen.addEventListener('click', openNote);
    bar.appendChild(pname); bar.appendChild(pen);

    var hero = document.createElement('div'); hero.className = 'hero';
    var heroNum = document.createElement('div'); heroNum.className = 'heroNum';
    var num = document.createElement('div'); num.className = 'num';
    var label = document.createElement('div'); label.className = 'numLabel'; label.textContent = '连续天数';
    heroNum.appendChild(num); heroNum.appendChild(label);

    var cta = document.createElement('button'); cta.className = 'cta';
    cta.addEventListener('click', function () { checkIn(h); });

    var hintWrap = document.createElement('div'); hintWrap.className = 'hintWrap';

    // 顶部三格统计：当前连续 / 最长连续 / 总打卡
    function statBlock() {
      var s = document.createElement('div'); s.className = 'stat';
      var b = document.createElement('b'); var t = document.createElement('span');
      s.appendChild(b); s.appendChild(t);
      return { root: s, b: b, t: t };
    }
    h.stCur = statBlock(); h.stBest = statBlock(); h.stTot = statBlock();
    var stats = document.createElement('div'); stats.className = 'stats';
    stats.appendChild(h.stCur.root); stats.appendChild(h.stBest.root); stats.appendChild(h.stTot.root);

    hero.appendChild(heroNum); hero.appendChild(cta); hero.appendChild(hintWrap); hero.appendChild(stats);

    var week = document.createElement('div'); week.className = 'week';
    week.innerHTML = WD.map(function (w) { return '<span>' + w + '</span>'; }).join('');

    var cal = document.createElement('div'); cal.className = 'cal';

    page.appendChild(bar); page.appendChild(hero); page.appendChild(week); page.appendChild(cal);

    h.el = page; h.numEl = num; h.cta = cta; h.hintWrap = hintWrap; h.dotsEl = dots; h.calEl = cal; h.pnText = pnText;
    return page;
  }

  function paint(h) {
    var info = compute(h);
    setNumber(h, info.days);

    var done = !!h.checked[TODAY_KEY];
    if (done) {
      h.cta.classList.add('done');
      h.cta.innerHTML = CHECK_SVG + '<span>打卡成功</span>';
    } else {
      h.cta.classList.remove('done');
      h.cta.innerHTML = '<span>打 卡</span>';
    }

    if (info.broken) {
      h.hintWrap.innerHTML = '<span class="dead">已断卡 · 从今天重新开始</span>';
    } else if (info.gap > 0) {
      if (info.makable) {
        var btn = document.createElement('button');
        btn.className = 'hint';
        btn.innerHTML = '<span class="a">断卡 ' + info.gap + ' 天</span><span class="sep"></span><span class="b">补签恢复 ' + info.restored + '</span>';
        btn.addEventListener('click', function () { if (doMakeup(h)) { paint(h); popToday(h); } });
        h.hintWrap.innerHTML = '';
        h.hintWrap.appendChild(btn);
      } else {
        h.hintWrap.innerHTML = '<span class="dead">断卡 ' + info.gap + ' 天 · 补签额度不足</span>';
      }
    } else {
      h.hintWrap.innerHTML = '';
    }

    var total = 0;
    for (var kk in h.checked) if (h.checked.hasOwnProperty(kk)) total++;
    h.stCur.b.textContent = String(info.days);
    h.stCur.t.textContent = '当前连续';
    h.stBest.b.textContent = String(longestStreak(h));
    h.stBest.t.textContent = '最长连续';
    h.stTot.b.textContent = String(total);
    h.stTot.t.textContent = '总打卡';

    paintCells(h);
  }

  function popToday(h) {
    if (!h.todayCell) return;
    h.todayCell.classList.remove('pop');
    void h.todayCell.offsetWidth;
    h.todayCell.classList.add('pop');
  }

  function checkIn(h) {
    // 已经打过：再点一次 = 取消今天的打卡
    if (h.checked[TODAY_KEY]) {
      delete h.checked[TODAY_KEY];
      persist();
      paint(h);
      toast('已取消打卡');
      return;
    }
    // 断卡但还在补签窗口里：先补齐缺口再打卡，避免把前面的连续段清零
    var info = compute(h);
    if (info.gap > 0 && info.makable) doMakeup(h);
    var rec = nowRec();
    h.checked[TODAY_KEY] = rec;
    persist();
    paint(h);
    popToday(h);
    toast('打卡成功 · ' + hhmm(rec.hh, rec.mm));
    if (navigator.vibrate) navigator.vibrate(12);
  }

  function updateDots() {
    habits.forEach(function (h) {
      var html = '';
      for (var i = 0; i < habits.length; i++) {
        html += '<span class="dt' + (i === idx ? ' on' : '') + '"></span>';
      }
      h.dotsEl.innerHTML = html;
    });
  }

  function mountPages() {
    PAGER.innerHTML = '';
    habits.forEach(function (h) {
      var p = createPage(h);
      PAGER.appendChild(p);
      buildCalendar(h, h.calEl);
      h.numEl.style.setProperty('--n', SIZE + 'px');
      buildNumber(h, compute(h).days, true);
      paint(h);
    });
    updateDots();
    applyPager(0, false);
  }

  /* ================= 横向拖拽 ================= */
  function applyPager(offset, animate) {
    PAGER.style.transition = animate ? 'transform .34s cubic-bezier(.22,.61,.36,1)' : 'none';
    PAGER.style.transform = 'translateX(' + (-idx * W + offset) + 'px)';
  }

  var drag = null;
  var hMoved = false; // 本次按下之后有没有发生横向拖动（用来吞掉误触的 click）

  PAGER.addEventListener('pointerdown', function (e) {
    if (e.target.closest('button')) return;
    hMoved = false;
    drag = { x: e.clientX, y: e.clientY, dx: 0, lock: null };
  });

  PAGER.addEventListener('pointermove', function (e) {
    if (!drag) return;
    var dx = e.clientX - drag.x;
    var dy = e.clientY - drag.y;
    if (!drag.lock) {
      if (Math.abs(dy) > 8 && Math.abs(dy) >= Math.abs(dx)) { drag.lock = 'y'; return; }
      if (Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy)) { drag.lock = 'x'; }
      else return;
    }
    if (drag.lock !== 'x') return;
    drag.dx = dx;
    if (Math.abs(dx) > 6) hMoved = true;
    var d = dx;
    if ((idx === 0 && dx > 0) || (idx === habits.length - 1 && dx < 0)) d = dx * 0.32;
    applyPager(d, false);
  });

  function endDrag() {
    if (!drag) return;
    var dx = drag.dx || 0;
    var locked = drag.lock;
    drag = null;
    if (locked === 'x') {
      if (dx < -60 && idx < habits.length - 1) { idx++; persist(); }
      else if (dx > 60 && idx > 0) { idx--; persist(); }
    }
    applyPager(0, true);
    updateDots();
  }

  PAGER.addEventListener('pointerup', endDrag);
  PAGER.addEventListener('pointercancel', endDrag);
  PAGER.addEventListener('pointerleave', function () { if (drag && drag.lock === 'x') endDrag(); });

  /* ================= 某天详情 ================= */
  var daySheet = $('daySheet'), dayScrim = $('dayScrim');
  var dayCtx = null;

  function onDayTap(h, d) {
    if (hMoved) return; // 刚才那一下是横滑翻页，不是点日期
    openDay(h, d);
  }

  function openDay(h, d) {
    dayCtx = { h: h, d: d };
    $('dsDate').textContent = d.getFullYear() + '年' + (d.getMonth() + 1) + '月' +
      d.getDate() + '日 · 周' + WD[iso(d) - 1];

    var rec = h.checked[key(d)];
    var big = $('dsBig'), sub = $('dsSub');
    big.className = 'dsBig';
    if (d.getTime() > TODAY.getTime()) {
      big.classList.add('miss');
      big.textContent = '—';
      sub.textContent = '这一天还没到';
    } else if (!rec) {
      big.classList.add('miss');
      big.textContent = '未打卡';
      sub.textContent = d.getTime() === TODAY.getTime() ? '今天还没打卡' : '那天没有打卡记录';
    } else if (rec.mk) {
      big.classList.add('mk');
      big.textContent = '补签';
      sub.textContent = (rec.dm || '') + hhmm(rec.hh, rec.mm) + ' 补上';
    } else {
      big.textContent = hhmm(rec.hh, rec.mm);
      sub.textContent = '打卡成功';
    }

    var note = h.notes[key(d)];
    var noteEl = $('dsNote');
    if (note) {
      $('dsNoteText').textContent = note;
      noteEl.classList.add('on');
    } else {
      noteEl.classList.remove('on');
    }

    dayScrim.classList.add('on');
    daySheet.classList.add('on');
  }

  function closeDay() {
    dayScrim.classList.remove('on');
    daySheet.classList.remove('on');
  }
  dayScrim.addEventListener('click', closeDay);

  $('dsPen').addEventListener('click', function () {
    if (!dayCtx) return;
    var c = dayCtx;
    closeDay();
    setTimeout(function () { openNoteFor(c.h, c.d); }, 180);
  });

  /* ================= 项目面板 ================= */
  var sheet = $('sheet'), scrim = $('scrim'), sheetList = $('sheetList');
  var pendingDelete = null;

  function openSheet() {
    pendingDelete = null;
    renderSheet();
    // 行逐条上浮入场
    Array.prototype.forEach.call(sheetList.children, function (r, i) {
      r.style.animation = 'none';
      void r.offsetWidth;
      r.style.animation = 'rise .3s cubic-bezier(.22,.61,.36,1) both';
      r.style.animationDelay = (60 + i * 45) + 'ms';
    });
    scrim.classList.add('on');
    sheet.classList.add('on');
  }
  function closeSheet() {
    scrim.classList.remove('on');
    sheet.classList.remove('on');
  }
  scrim.addEventListener('click', closeSheet);

  function renderSheet() {
    sheetList.innerHTML = '';
    habits.forEach(function (h, i) {
      var row = document.createElement('div');
      row.className = 'srow' + (i === idx ? ' on' : '');
      var info = compute(h);

      var glyph = document.createElement('span'); glyph.className = 'glyph';
      glyph.textContent = h.glyph;
      var nameEl = document.createElement('span'); nameEl.className = 'sname';
      nameEl.textContent = h.name;
      var numEl = document.createElement('span'); numEl.className = 'snum';
      numEl.textContent = String(info.days);
      var unitEl = document.createElement('span'); unitEl.className = 'sunit';
      unitEl.textContent = '天';

      row.appendChild(glyph); row.appendChild(nameEl);
      row.appendChild(numEl); row.appendChild(unitEl);

      if (habits.length > 1) {
        var del = document.createElement('button');
        del.className = 'del';
        del.innerHTML = pendingDelete === h.id ? '<span class="rm">删除</span>' : '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#d2d2d2" stroke-width="2" stroke-linecap="round"><path d="M18 6L6 18M6 6l12 12"></path></svg>';
        del.addEventListener('click', function (e) {
          e.stopPropagation();
          if (pendingDelete === h.id) { removeHabit(h.id); return; }
          pendingDelete = h.id;
          renderSheet();
        });
        row.appendChild(del);
      } else {
        var pad = document.createElement('span'); pad.style.width = '44px';
        row.appendChild(pad);
      }

      row.addEventListener('click', function () {
        idx = i;
        applyPager(0, true);
        updateDots();
        closeSheet();
        persist();
      });
      sheetList.appendChild(row);
    });
  }

  function removeHabit(id) {
    var i = -1;
    for (var k = 0; k < habits.length; k++) if (habits[k].id === id) { i = k; break; }
    if (i < 0) return;
    habits.splice(i, 1);
    if (idx > habits.length - 1) idx = habits.length - 1;
    if (idx < 0) idx = 0;
    pendingDelete = null;
    closeSheet();
    mountPages();
    persist();
  }

  $('addRow').addEventListener('click', function () {
    closeSheet();
    openDialog();
  });

  /* ================= 新建对话框 ================= */
  var dlgWrap = $('dlgWrap'), dlgInput = $('dlgInput');

  function openDialog() {
    dlgInput.value = '';
    dlgWrap.classList.add('on');
    setTimeout(function () { dlgInput.focus(); }, 200);
  }
  function closeDialog() { dlgWrap.classList.remove('on'); }

  function submitDialog() {
    var name = dlgInput.value.trim();
    if (!name) { dlgInput.focus(); return; }
    closeDialog();
    habits.push({
      id: 'h' + Date.now(),
      name: name,
      glyph: name.substring(0, 1),
      checked: {},
      notes: {},
      cards: CARDS
    });
    idx = habits.length - 1;
    mountPages();
    persist();
  }

  $('dlgCancel').addEventListener('click', closeDialog);
  $('dlgOk').addEventListener('click', submitDialog);
  dlgInput.addEventListener('keydown', function (e) { if (e.key === 'Enter') submitDialog(); });
  dlgWrap.addEventListener('click', function (e) { if (e.target === dlgWrap) closeDialog(); });

  /* ================= 记事 ================= */
  var note = $('note'), noteInput = $('noteInput');
  var noteCtx = null; // { h: 项目, k: 日期 key, d: Date }

  function openNote() { openNoteFor(habits[idx], TODAY); }

  function openNoteFor(h, d) {
    noteCtx = { h: h, k: key(d), d: d };
    noteInput.value = h.notes[noteCtx.k] || '';
    $('noteTitle').textContent = h.name;
    $('noteDate').textContent = d.getFullYear() + '年' + (d.getMonth() + 1) + '月' +
      d.getDate() + '日 · 周' + WD[iso(d) - 1];
    note.classList.add('open');
    setTimeout(function () { noteInput.focus(); }, 340);
  }
  function closeNote() {
    note.classList.remove('open');
    noteInput.blur();
  }
  function saveNote() {
    if (!noteCtx) return closeNote();
    var t = noteInput.value.trim();
    var h = noteCtx.h;
    if (t) h.notes[noteCtx.k] = t; else delete h.notes[noteCtx.k];
    persist();
    paintCells(h);
    closeNote();
    toast('已保存');
  }

  $('noteBack').addEventListener('click', closeNote);
  $('noteSave').addEventListener('click', saveNote);

  /* ================= 自适应缩放 ================= */
  var device = $('device');

  /* ================= Toast 轻提示 ================= */
  var toastEl = document.createElement('div'); toastEl.className = 'toast';
  device.appendChild(toastEl);
  var toastTimer = null;
  function toast(msg) {
    toastEl.textContent = msg;
    toastEl.classList.add('on');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toastEl.classList.remove('on'); }, 1700);
  }

  function fit() {
    var s = Math.min(1, (window.innerWidth - 40) / 390, (window.innerHeight - 40) / 844);
    device.style.transform = 'scale(' + s + ')';
  }
  window.addEventListener('resize', fit);
  fit();

  /* ================= 启动 ================= */
  mountPages();

  function assert(cond, msg) { if (!cond) { console.log('FAIL: ' + msg); process.exitCode = 1; } else { console.log('ok   ' + msg); } }

  var raw = localStorage.getItem('streak.data.v1');
  assert(!!raw, '首次访问已写入 localStorage');
  var d0 = JSON.parse(raw);
  assert(Array.isArray(d0.habits) && d0.habits.length === 3, '入库 3 个项目');

  var h0 = habits[0];
  assert(!h0.checked[TODAY_KEY], '初始今天未打卡');
  checkIn(h0);
  assert(!!h0.checked[TODAY_KEY], '打卡后今天有记录');
  assert(h0.cta.textContent.indexOf('打卡成功') >= 0, '按钮显示「打卡成功」');
  assert(toastEl.classList.contains('on') && toastEl.textContent.indexOf('打卡成功') === 0, 'Toast: ' + toastEl.textContent);
  checkIn(h0);
  assert(!h0.checked[TODAY_KEY], '再点一次已取消');
  assert(h0.cta.textContent.indexOf('打 卡') >= 0, '按钮回到「打 卡」');
  assert(toastEl.textContent === '已取消打卡', 'Toast「已取消打卡」');

  checkIn(h0);
  var info0 = compute(h0);
  assert(info0.days === 351, '早起打卡后 351');
  assert(+h0.stCur.b.textContent === 351 && h0.stCur.t.textContent === '当前连续', '当前连续 = 351');
  assert(+h0.stBest.b.textContent === 350 && h0.stBest.t.textContent === '最长连续', '最长连续 = 350');
  assert(+h0.stTot.b.textContent === Object.keys(h0.checked).length && h0.stTot.t.textContent === '总打卡', '总打卡 = ' + h0.stTot.b.textContent);
  assert(longestStreak(habits[1]) === 12, '阅读最长连续 = 12');

  openSheet();
  assert(sheet.classList.contains('on'), '面板打开');
  assert(sheetList.children.length === 3, '面板列出 3 行');
  sheetList.children[2].click();
  assert(idx === 2, '点击「健身」行 → idx = 2');
  assert(!sheet.classList.contains('on'), '切换后面板收起');
  assert(habits[2].pnText.textContent === '健身', '顶部名字 = 健身');

  openNoteFor(habits[1], back(2));
  noteInput.value = '补一条测试笔记';
  $('noteSave').click();
  assert(habits[1].notes[key(back(2))] === '补一条测试笔记', '保存记事入库');
  assert(!note.classList.contains('open'), '保存后自动返回');
  assert(toastEl.textContent === '已保存', 'Toast「已保存」');

  openNoteFor(habits[1], back(4));
  noteInput.value = '草稿不该被保存';
  $('noteBack').click();
  assert(!note.classList.contains('open') && !habits[1].notes[key(back(4))], '返回不保存，草稿丢弃');

  var d = JSON.parse(localStorage.getItem('streak.data.v1'));
  assert(d.idx === 2, '当前项目序号入库 (idx=2)');
  assert(d.habits[1].notes[key(back(2))] === '补一条测试笔记', '记事已入库');
  assert(d.habits[0].checked[TODAY_KEY] && typeof d.habits[0].checked[TODAY_KEY].hh === 'number', '打卡时刻已入库');
  assert(typeof d.habits[0].cards === 'number', '补签额度已入库');

  var i1 = compute(habits[1]);
  assert(i1.days === 12 && i1.gap === 2 && i1.makable, '阅读断 2 天可补');
  doMakeup(habits[1]);
  assert(compute(habits[1]).days === 14 && compute(habits[1]).gap === 0, '补签后 14、缺口归零');
  var dm = JSON.parse(localStorage.getItem('streak.data.v1'));
  assert(dm.habits[1].cards === CARDS - 2, '补签扣额度并入库');

  console.log('---- 全部断言执行完毕 ----');

})();
