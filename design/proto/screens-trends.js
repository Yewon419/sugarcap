'use strict';
// Phase 2-4: 추이 탭 안 A·B·C. 메인 화면 문법(소제목 → 큰 숫자 → 캡션, 벽 색 바탕, 액센트 하나)을 잇는다.
// SPEC §9.5: 당·카페인은 단위가 달라 따로 본다. 주 보기 = 날마다 합계 + 하루 기준 점선.
// 월 보기(주별 하루 평균)·지난주 대비는 Pro. 날짜를 누르면 그날 기록 시트(renderDayLog)가 열린다.

const trendSide = () => ui.trendSide ?? 'sugar';
const trendRange = () => ui.trendRange ?? 'week';
const WEEKDAY = '일월화수목금토';

function dayLabel(key) {
  const d = new Date(`${key}T12:00:00`);
  return { md: `${d.getMonth() + 1}/${d.getDate()}`, wd: WEEKDAY[d.getDay()], date: d };
}

/** 오늘을 끝으로 거슬러 n일(오래된 날이 먼저). */
function lastDays(n) {
  const today = dayKey(now());
  return Array.from({ length: n }, (_, i) => shiftDay(today, i - n + 1));
}

function usedOn(key, side) {
  return totalsOf(key)[side].used;
}

const hasEntries = key => S.entries.some(e => dayKey(e.at) === key);

function weekStats(side, endOffset = 0) {
  const days = lastDays(7 + endOffset).slice(0, 7);
  const limit = limitOf(side);
  const values = days.map(k => usedOn(k, side));
  const avg = values.reduce((a, b) => a + b, 0) / days.length;
  const within = values.filter(v => v <= limit).length;
  return { days, values, avg, within, limit };
}

function trendHeader(title) {
  const side = trendSide();
  const range = trendRange();
  return `
    <div class="trend-head">
      <div class="date-label">${title}</div>
      <div class="trend-controls">
        <div class="segmented compact">${SIDE_ORDER.map(s =>
          `<button class="${s === side ? 'on' : ''}" data-a="trendSide" data-v="${s}">${SIDES[s].label}</button>`).join('')}</div>
        <div class="segmented compact">${[['week', '주'], ['month', '월']].map(([r, label]) =>
          `<button class="${r === range ? 'on' : ''}" data-a="trendRange" data-v="${r}">${label}${r === 'month' && !S.pro ? ` ${ICON.lock}` : ''}</button>`).join('')}</div>
      </div>
    </div>`;
}

/** 지난주 대비(Pro). 무료면 잠긴 줄로 보여 주고 누르면 페이월. */
function deltaLine(side) {
  const meta = SIDES[side];
  const cur = weekStats(side).avg;
  const prev = weekStats(side, 7).avg;
  if (!S.pro) return `<button class="delta locked" data-a="paywall">${ICON.lock} 지난주보다 얼마나 줄었는지 보기</button>`;
  if (prev === 0) return '<div class="delta">지난주 기록이 없어요</div>';
  const diff = cur - prev;
  return `<div class="delta ${diff <= 0 ? 'down' : 'up'}">지난주보다 하루 ${num(Math.abs(diff))} ${meta.unit} ${diff <= 0 ? '줄었어요' : '늘었어요'}</div>`;
}

// ---------- A: 숫자 먼저 ----------
function renderTrendsNumber() {
  const side = trendSide();
  const meta = SIDES[side];
  const range = trendRange();
  let hero, chart;
  if (range === 'week') {
    const w = weekStats(side);
    hero = `<div class="kicker">이번 주 하루 평균 ${meta.label}</div>
      <div class="number-row"><span class="hero-number">${num(w.avg)}</span><span class="hero-unit">${meta.unit}</span>
        <span class="limit">/${num(w.limit)} ${meta.unit}</span></div>
      ${deltaLine(side)}`;
    chart = barChart(w.days.map((k, i) => ({ key: k, value: w.values[i], label: dayLabel(k).wd, today: i === 6 })), w.limit, meta.unit);
  } else {
    const weeks = [3, 2, 1, 0].map(back => ({ back, ...weekStats(side, back * 7) }));
    hero = `<div class="kicker">최근 4주 하루 평균 ${meta.label}</div>
      <div class="number-row"><span class="hero-number">${num(weeks.reduce((a, w) => a + w.avg, 0) / 4)}</span><span class="hero-unit">${meta.unit}</span></div>
      <div class="feed-caption">주마다 하루 평균이에요.</div>`;
    chart = barChart(weeks.map(w => ({ key: null, value: w.avg, label: w.back === 0 ? '이번 주' : `${w.back}주 전`, today: w.back === 0 })), limitOf(side), meta.unit);
  }
  return `<div class="trends">
    ${trendHeader('추이')}
    <div class="trend-hero">${hero}</div>
    <div class="trend-card">${chart}</div>
    <div class="caption-note trend-note">${range === 'week' ? '막대를 누르면 그날 기록을 봐요.' : '점선은 지금 하루 기준이에요.'}</div>
  </div>`;
}

function barChart(items, limit, unit) {
  const max = Math.max(limit * 1.25, ...items.map(i => i.value), 1);
  const H = 190;
  const limitY = H - (limit / max) * H;
  return `<div class="bars" style="--h:${H}px">
    <div class="limit-line" style="top:${limitY}px"><span>기준 ${num(limit)} ${unit}</span></div>
    ${items.map(i => {
      const h = Math.max(3, (i.value / max) * H);
      const over = i.value > limit;
      const attrs = i.key ? `data-a="openDayLog" data-v="${i.key}"` : '';
      return `<button class="bar-col" ${attrs} ${i.key ? '' : 'disabled'} aria-label="${i.label} ${num(i.value)} ${unit}">
        <span class="bar-val">${i.value > 0 ? num(i.value) : ''}</span>
        <span class="bar ${over ? 'over' : ''} ${i.today ? 'is-today' : ''}" style="height:${h}px"></span>
        <span class="bar-label ${i.today ? 'is-today' : ''}">${i.label}</span>
      </button>`;
    }).join('')}
  </div>`;
}

// ---------- B: 컵 달력 ----------
function renderTrendsCups() {
  const side = trendSide();
  const meta = SIDES[side];
  const range = trendRange();
  const limit = limitOf(side);
  const cup = key => {
    const empty = !hasEntries(key) && key !== dayKey(now());
    const left = Math.max(0, limit - usedOn(key, side));
    const step = cupStep(left, limit);
    const { md, wd } = dayLabel(key);
    return `<button class="cup-day ${key === dayKey(now()) ? 'is-today' : ''} ${empty ? 'empty' : ''}" data-a="openDayLog" data-v="${key}" aria-label="${md} 남은 ${meta.label} ${num(left)} ${meta.unit}">
      <span class="cup-thumb" style="background-image:url('${cupAsset(meta.cupSet, empty ? 0 : step)}')"></span>
      <span class="cup-date">${range === 'week' ? wd : dayLabel(key).date.getDate()}</span>
      ${range === 'week' ? `<span class="cup-left">${empty ? '—' : `${num(left)}`}</span>` : ''}
    </button>`;
  };
  let body;
  if (range === 'week') {
    const w = weekStats(side);
    body = `<div class="trend-hero">
        <div class="kicker">이번 주 기준 안에서 마신 날</div>
        <div class="number-row"><span class="hero-number">${w.within}</span><span class="hero-unit">일</span><span class="limit">/7일</span></div>
        ${deltaLine(side)}
      </div>
      <div class="trend-card"><div class="cup-week">${w.days.map(cup).join('')}</div>
        <div class="cup-legend">컵에 남은 만큼이 그날 덜 마신 ${meta.label}이에요. 숫자는 남은 ${meta.unit}.</div></div>`;
  } else {
    const today = new Date(now());
    const first = new Date(today.getFullYear(), today.getMonth(), 1);
    const daysInMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();
    const keys = Array.from({ length: daysInMonth }, (_, i) => {
      const d = new Date(first); d.setDate(i + 1);
      return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    });
    const todayKey = dayKey(now());
    const upto = keys.filter(k => k <= todayKey);
    const within = upto.filter(k => usedOn(k, side) <= limit).length;
    body = `<div class="trend-hero">
        <div class="kicker">${today.getMonth() + 1}월 기준 안에서 마신 날</div>
        <div class="number-row"><span class="hero-number">${within}</span><span class="hero-unit">일</span><span class="limit">/${upto.length}일</span></div>
      </div>
      <div class="trend-card"><div class="cup-weekdays">${[...WEEKDAY].map(d => `<span>${d}</span>`).join('')}</div>
        <div class="cup-month">${'<span></span>'.repeat(first.getDay())}${keys.map(k => (k <= todayKey ? cup(k) : `<span class="cup-day future">${Number(k.slice(-2))}</span>`)).join('')}</div></div>`;
  }
  return `<div class="trends">${trendHeader('추이')}${body}</div>`;
}

// ---------- C: 하루 줄 ----------
function renderTrendsRows() {
  const side = trendSide();
  const meta = SIDES[side];
  const range = trendRange();
  const limit = limitOf(side);
  const days = lastDays(range === 'week' ? 7 : 28).reverse();
  const w = weekStats(side);
  const rows = days.map(key => {
    const used = usedOn(key, side);
    const { md, wd } = dayLabel(key);
    const ratio = Math.min(used / limit, 1.4);
    const over = used > limit;
    return `<button class="day-row" data-a="openDayLog" data-v="${key}">
      <span class="day-row-date"><b>${md}</b> ${wd}</span>
      <span class="day-row-bar"><i class="${over ? 'over' : ''}" style="width:${(ratio / 1.4) * 100}%"></i><em style="left:${(1 / 1.4) * 100}%"></em></span>
      <span class="day-row-num">${hasEntries(key) ? `${num(used)}<small>${meta.unit}</small>` : '<small>기록 없음</small>'}</span>
    </button>`;
  }).join('');
  return `<div class="trends">
    ${trendHeader('추이')}
    <div class="trend-hero">
      <div class="kicker">이번 주 하루 평균 ${meta.label}</div>
      <div class="number-row"><span class="hero-number">${num(w.avg)}</span><span class="hero-unit">${meta.unit}</span><span class="limit">/${num(limit)} ${meta.unit}</span></div>
      ${deltaLine(side)}
    </div>
    <div class="trend-card rows">${rows}</div>
    <div class="caption-note trend-note">세로 선이 하루 기준이에요. 줄을 누르면 그날 기록을 봐요.</div>
  </div>`;
}

const TREND_ACTIONS = {
  trendSide: v => { ui.trendSide = v; },
  trendRange: v => {
    if (v === 'month' && !S.pro) { ui.sheet = 'paywall'; return; }
    ui.trendRange = v;
  },
  paywall: () => { ui.sheet = 'paywall'; },
};
