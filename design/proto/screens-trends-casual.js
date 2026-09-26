'use strict';
// 추이 캐주얼(기본). 대표님 요청(2026-09-26): 그래픽으로 캐주얼하고 멋지게.
// 기존 그림 자산(컵 사진·방울·캐릭터)만 쓴다. 도우미는 screens-trends.js·app.js 전역.

function renderTrendsCasual() {
  const side = trendSide();
  const meta = SIDES[side];
  const limit = limitOf(side);
  const todayKey = dayKey(now());
  const drop = `../assets/drops/${side}.png`;

  if (trendRange() === 'month') return renderDropCalendar(side, meta, limit, todayKey, drop);

  const w = weekStats(side);
  const given = w.days.reduce((sum, k) => sum + Math.max(0, limit - usedOn(k, side)), 0);
  const good = w.within >= 5;
  const cups = w.days.map(key => {
    const used = usedOn(key, side);
    const left = Math.max(0, limit - used);
    const over = used - limit;
    const recorded = hasEntries(key) || key === todayKey;
    const { wd } = dayLabel(key);
    return `<button class="shelf-cup ${key === todayKey ? 'is-today' : ''}" data-a="openDayLog" data-v="${key}" aria-label="${wd}요일 남은 ${meta.label} ${num(left)} ${meta.unit}">
      ${over > 0 ? `<span class="over-tag">+${num(over)}</span>` : ''}
      <span class="shelf-glass ${recorded ? '' : 'blank'}" style="background-image:url('${cupAsset(meta.cupSet, recorded ? cupStep(left, limit) : 0)}')"></span>
      <span class="shelf-day">${wd}</span>
    </button>`;
  }).join('');

  return `<div class="trends casual ${side}">
    ${trendHeader('추이')}
    <section class="hero-card">
      <div class="hero-text">
        <div class="kicker">이번 주 기준 안에서 마신 날</div>
        <div class="number-row"><span class="hero-number">${w.within}</span><span class="hero-unit">일</span><span class="limit">/7일</span></div>
        <div class="hero-caption">${good ? `${meta.withGwa} 사이가 쑥쑥 가까워지는 중` : `하루 평균 ${num(w.avg)} ${meta.unit} 마셨어요`}</div>
      </div>
      <img class="hero-char ${good ? 'cheer' : ''}" src="${characterAsset(meta.char)}" alt="${meta.name}">
    </section>

    <section class="shelf">
      <div class="shelf-head"><span class="kicker">이번 주 컵</span><span class="shelf-hint">컵을 누르면 그날 기록</span></div>
      <div class="shelf-row">${cups}</div>
    </section>

    <section class="stat-row">
      <div class="stat-card drops">
        <img src="${drop}" alt="">
        <div><div class="stat-num">${num(given)}<small>${meta.unit}</small></div><div class="stat-label">이번 주 ${meta.name}에게 준 ${meta.label}</div></div>
      </div>
      ${deltaChip(side)}
    </section>
  </div>`;
}

/** 지난주 대비(Pro). 무료는 잠긴 카드. */
function deltaChip(side) {
  const meta = SIDES[side];
  if (!S.pro) return `<button class="stat-card locked" data-a="paywall" data-v="delta">${ICON.lock}<div class="stat-label">지난주와<br>비교하기</div></button>`;
  const cur = weekStats(side).avg;
  const prev = weekStats(side, 7).avg;
  if (prev === 0) return '<div class="stat-card"><div class="stat-label">지난주 기록이<br>없어요</div></div>';
  const diff = cur - prev;
  return `<div class="stat-card delta-card ${diff <= 0 ? 'down' : 'up'}">
    <div class="stat-arrow">${diff <= 0 ? '↓' : '↑'}</div>
    <div><div class="stat-num">${num(Math.abs(diff))}<small>${meta.unit}</small></div><div class="stat-label">지난주보다 하루 ${diff <= 0 ? '덜' : '더'}</div></div>
  </div>`;
}

/** 월(Pro): 방울 달력. 날마다 남긴 만큼 방울이 커진다. */
function renderDropCalendar(side, meta, limit, todayKey, drop) {
  const today = new Date(now());
  const first = new Date(today.getFullYear(), today.getMonth(), 1);
  const days = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();
  const keys = Array.from({ length: days }, (_, i) => `${first.getFullYear()}-${pad(first.getMonth() + 1)}-${pad(i + 1)}`);
  const upto = keys.filter(k => k <= todayKey);
  const within = upto.filter(k => usedOn(k, side) <= limit).length;
  const given = upto.reduce((sum, k) => sum + Math.max(0, limit - usedOn(k, side)), 0);
  const cell = key => {
    if (key > todayKey) return `<span class="drop-cell future"><span class="drop-day">${Number(key.slice(-2))}</span></span>`;
    const left = Math.max(0, limit - usedOn(key, side));
    const size = left > 0 ? Math.round(12 + 26 * Math.min(1, left / limit)) : 0;
    return `<button class="drop-cell ${key === todayKey ? 'is-today' : ''}" data-a="openDayLog" data-v="${key}" aria-label="${Number(key.slice(-2))}일 남은 ${num(left)} ${meta.unit}">
      <span class="drop-spot">${size ? `<img src="${drop}" style="width:${size}px;height:${size}px" alt="">` : '<i class="drop-none"></i>'}</span>
      <span class="drop-day">${Number(key.slice(-2))}</span>
    </button>`;
  };
  return `<div class="trends casual ${side}">
    ${trendHeader('추이')}
    <section class="hero-card">
      <div class="hero-text">
        <div class="kicker">${today.getMonth() + 1}월 ${meta.name}에게 준 ${meta.label}</div>
        <div class="number-row"><span class="hero-number">${num(given)}</span><span class="hero-unit">${meta.unit}</span></div>
        <div class="hero-caption">기준 안에서 마신 날 ${within}일 / ${upto.length}일</div>
      </div>
      <img class="hero-char" src="${characterAsset(meta.char)}" alt="${meta.name}">
    </section>
    <section class="shelf">
      <div class="shelf-head"><span class="kicker">방울 달력</span><span class="shelf-hint">남긴 만큼 방울이 커요</span></div>
      <div class="drop-weekdays">${[...WEEKDAY].map(d => `<span>${d}</span>`).join('')}</div>
      <div class="drop-grid">${'<span></span>'.repeat(first.getDay())}${keys.map(cell).join('')}</div>
    </section>
  </div>`;
}
