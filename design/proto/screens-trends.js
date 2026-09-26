'use strict';
// 추이 탭 공통 도우미. 확정안(캐주얼, 2026-09-26)은 screens-trends-casual.js. 메인 화면 문법(소제목 → 큰 숫자 → 캡션, 벽 색 바탕, 액센트 하나)을 잇는다.
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

const TREND_ACTIONS = {
  trendSide: v => { ui.trendSide = v; },
  trendRange: v => {
    if (v === 'month' && !S.pro) { ui.sheet = 'paywall'; return; }
    ui.trendRange = v;
  },
  paywall: () => { ui.sheet = 'paywall'; },
};
