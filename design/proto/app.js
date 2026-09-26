'use strict';
// 슈가캡 HTML 프로토타입. 규칙은 SPEC §4.1·§4.7·§9.5를 따른다.
// 오늘 화면은 iOS 현행(대표님 확정 디자인)을 그대로 옮겼고, 나머지는 Phase 2에서 다시 설계한다.

const STORE_KEY = 'sugarcap-proto-v2';
const ASSETS = '../../SugarCap/Resources';
const CATALOG_URL = '../../data/catalog.json';

// ---------- 규칙 ----------
const SIDES = {
  sugar: { label: '당', unit: 'g', char: 'roshu', name: '로슈', withGwa: '로슈와', withIga: '로슈가', cupSet: 'strawberry-latte', limitKey: 'sugarG' },
  caffeine: { label: '카페인', unit: 'mg', char: 'kain', name: '카인', withGwa: '카인과', withIga: '카인이', cupSet: 'iced-americano', limitKey: 'caffeineMg' },
};
const SIDE_ORDER = ['sugar', 'caffeine'];
const CUP_STEPS = [0, 10, 20, 30, 40, 50, 70, 80, 100];
const MAX_LEVEL = 10;
const STAGE_NAMES = [
  '처음 만난 사이', '눈인사하는 사이', '이름 부르는 사이', '반가운 사이', '기다려지는 사이',
  '편한 사이', '친한 사이', '단짝 사이', '속마음 나누는 사이', '둘도 없는 사이',
];

const cupAsset = (set, step) => `${ASSETS}/Assets.xcassets/cup-${set}-${step}.imageset/${step}.png`;
const characterAsset = char => `${ASSETS}/Shared.xcassets/character-${char}.imageset/${char}.png`;

/** CupLevel.step: 남은 비율 이하 중 가장 높은 단계. 0은 정확히 0일 때만, 100은 한 잔도 안 줄었을 때만. */
function cupStep(remaining, limit) {
  if (limit <= 0) return 0;
  const ratio = remaining / limit;
  if (ratio <= 0) return 0;
  if (ratio >= 1) return 100;
  const percent = ratio * 100;
  return Math.max(10, ...CUP_STEPS.filter(s => s > 0 && s <= percent));
}

/** 먹이기 1회 적립 = 1 + round(남은/기준 × 9), 1~10점. */
function affinityPoints(left, limit) {
  if (limit <= 0) return 1;
  return 1 + Math.round(Math.min(1, Math.max(0, left / limit)) * 9);
}
const threshold = level => 15 * level * (level - 1);
function levelOf(points) {
  let level = 1;
  while (level < MAX_LEVEL && points >= threshold(level + 1)) level += 1;
  return level;
}
const stageName = level => STAGE_NAMES[Math.min(Math.max(level, 1), MAX_LEVEL) - 1];

// ---------- 상태 ----------
const freshState = () => ({
  pro: false,
  clockOffset: 0,
  settings: { sugarG: 50, caffeineMg: 400, boundary: 4, closeFrom: 20 },
  entries: [],
  days: {},
  points: { roshu: 0, kain: 0 },
  firstDay: null,
  favorites: [],
  talks: {},
});

let S = loadState();
let CATALOG = null;
const ui = {
  tab: 'today',
  side: 'sugar',
  sheet: null,
  pushed: null,
  panelSheet: null,
  cover: null,
  credit: null,
  query: '',
  globalQuery: '',
  dayLog: null,
  category: '전체',
  toast: null,
  variants: {},
};

function loadState() {
  const raw = localStorage.getItem(STORE_KEY);
  if (!raw) return freshState();
  try {
    return { ...freshState(), ...JSON.parse(raw) };
  } catch (error) {
    console.error('저장된 상태를 읽지 못해 새로 시작함', error);
    return freshState();
  }
}
function saveState() { localStorage.setItem(STORE_KEY, JSON.stringify(S)); }

// ---------- 시간·하루 ----------
const now = () => Date.now() + S.clockOffset;
const pad = n => String(n).padStart(2, '0');
function dayKey(t) {
  const d = new Date(t - S.settings.boundary * 3600e3);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
function shiftDay(key, n) {
  const d = new Date(`${key}T12:00:00`);
  d.setDate(d.getDate() + n);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
function isCloseWindowOpen() {
  const hour = new Date(now()).getHours();
  return hour >= S.settings.closeFrom || hour < S.settings.boundary;
}
const limitOf = side => S.settings[SIDES[side].limitKey];

function totalsOf(key) {
  let sugar = 0, caffeine = 0;
  for (const e of S.entries) {
    if (dayKey(e.at) !== key) continue;
    sugar += e.sugarG ?? 0;
    caffeine += e.caffeineMg ?? 0;
  }
  return {
    sugar: { used: sugar, left: Math.max(0, S.settings.sugarG - sugar), over: Math.max(0, sugar - S.settings.sugarG) },
    caffeine: { used: caffeine, left: Math.max(0, S.settings.caffeineMg - caffeine), over: Math.max(0, caffeine - S.settings.caffeineMg) },
  };
}

// ---------- 정산(§4.7) ----------
const dayRow = key => (S.days[key] ??= {});

/** 하루치 남은 양을 캐릭터에게 적립한다. 결과는 단계 상승 연출에 쓴다. */
function credit(key, left) {
  const row = dayRow(key);
  const results = SIDE_ORDER.map(side => {
    const char = SIDES[side].char;
    const before = levelOf(S.points[char]);
    const gained = affinityPoints(left[side], limitOf(side));
    S.points[char] += gained;
    return { side, gained, before, after: levelOf(S.points[char]) };
  });
  row.finalized = true;
  row.finalLeft = left;
  return results;
}

/** 앱을 연 날 표시 → 마감한 지난 날을 최종 값으로 확정 → 어제에 대해 물을 것을 고른다. */
function refreshSettlement() {
  const today = dayKey(now());
  S.firstDay ??= today;
  dayRow(today).opened = true;

  const credited = [];
  for (const [key, row] of Object.entries(S.days)) {
    if (key >= today || !row.closedAt || row.finalized) continue;
    const t = totalsOf(key);
    const left = { sugar: t.sugar.left, caffeine: t.caffeine.left };
    row.shrank = left.sugar < row.atClose.sugar - 1e-9 || left.caffeine < row.atClose.caffeine - 1e-9;
    credited.push(...credit(key, left));
  }
  if (credited.length) ui.credit = credited;
  saveState();
}

function pendingPrompt() {
  const today = dayKey(now());
  const yesterday = shiftDay(today, -1);
  const row = S.days[yesterday];
  if (row?.opened && !row.closedAt && !row.dismissed) return { kind: 'feed', day: yesterday };
  if (!row?.opened && !row?.asked && S.firstDay && yesterday >= S.firstDay) return { kind: 'ask', day: yesterday };
  return null;
}

// ---------- 형식 ----------
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const num = v => String(Math.round(v * 10) / 10);
const amount = (v, unit) => (v === null || v === undefined ? '미공개' : `${num(v)} ${unit}`);
const TEMP = { hot: 'HOT', iced: 'ICE', both: '' };
function dateLabel(t) {
  const d = new Date(t);
  return `${d.getMonth() + 1}월 ${d.getDate()}일 ${'일월화수목금토'[d.getDay()]}요일`;
}
function clockLabel(t) {
  const d = new Date(t);
  return `${d.getHours() % 12 || 12}:${pad(d.getMinutes())}`;
}
function timeLabel(t) {
  const d = new Date(t);
  const h = d.getHours();
  return `${h < 12 ? '오전' : '오후'} ${h % 12 || 12}:${pad(d.getMinutes())}`;
}

// ---------- 아이콘(SF Symbols 근사) ----------
const ICON = {
  heart: '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linejoin="round"><path d="M12 20.3s-7.8-4.7-7.8-10.4A4.4 4.4 0 0 1 12 7.1a4.4 4.4 0 0 1 7.8 2.8c0 5.7-7.8 10.4-7.8 10.4Z"/></svg>',
  plus: '<svg width="26" height="26" viewBox="0 0 26 26" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M13 3.5v19M3.5 13h19"/></svg>',
  moon: '<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"><path d="M13.2 4.2a8 8 0 1 0 7.1 11.6 6.6 6.6 0 0 1-7.1-11.6Z"/><path d="M17.5 3.5l.6 1.6 1.6.6-1.6.6-.6 1.6-.6-1.6-1.6-.6 1.6-.6Zm3 5 .4 1 1 .4-1 .4-.4 1-.4-1-1-.4 1-.4Z" fill="currentColor" stroke="none"/></svg>',
  cup: '<svg width="30" height="26" viewBox="0 0 30 26" fill="currentColor"><path d="M4 5.5c0-1.4 4.3-2.5 9.5-2.5S23 4.1 23 5.5v1.3h1.6a3.9 3.9 0 0 1 0 7.8h-2.2c-1.4 3.3-4.9 5.4-8.9 5.4S5.4 17.9 4.6 13.6 4 7.6 4 5.5Zm19 3.3v3.8h1.6a1.9 1.9 0 0 0 0-3.8H23Z"/><ellipse cx="13.5" cy="22.4" rx="11" ry="2.4"/></svg>',
  chart: '<svg width="26" height="24" viewBox="0 0 26 24" fill="currentColor"><rect x="2" y="11" width="6" height="11" rx="1.6"/><rect x="10" y="6" width="6" height="16" rx="1.6"/><rect x="18" y="2" width="6" height="20" rx="1.6"/></svg>',
  gear: '<svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M10.3 2h3.4l.5 2.6 1.6.7 2.2-1.5 2.4 2.4-1.5 2.2.7 1.6 2.6.5v3.4l-2.6.5-.7 1.6 1.5 2.2-2.4 2.4-2.2-1.5-1.6.7-.5 2.6h-3.4l-.5-2.6-1.6-.7-2.2 1.5-2.4-2.4 1.5-2.2-.7-1.6L2 13.7v-3.4l2.6-.5.7-1.6-1.5-2.2 2.4-2.4 2.2 1.5 1.6-.7ZM12 15.4a3.4 3.4 0 1 0 0-6.8 3.4 3.4 0 0 0 0 6.8Z"/></svg>',
  back: '<svg width="12" height="20" viewBox="0 0 12 20" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M10 2 2 10l8 8"/></svg>',
  star: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="m12 3.2 2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 17l-5.4 2.9 1.1-6.1-4.5-4.2 6.1-.8Z"/></svg>',
  starFill: '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="m12 3.2 2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 17l-5.4 2.9 1.1-6.1-4.5-4.2 6.1-.8Z"/></svg>',
  lock: '<svg width="12" height="14" viewBox="0 0 12 14" fill="currentColor"><path d="M3 6V4.2a3 3 0 0 1 6 0V6h.6c.8 0 1.4.6 1.4 1.4v4.9c0 .8-.6 1.4-1.4 1.4H2.4c-.8 0-1.4-.6-1.4-1.4V7.4C1 6.6 1.6 6 2.4 6H3Zm1.5 0h3V4.2a1.5 1.5 0 0 0-3 0V6Z"/></svg>',
  search: '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="6.8" cy="6.8" r="5"/><path d="m10.6 10.6 4 4" stroke-linecap="round"/></svg>',
};

// ---------- 화면 안(variant) 등록 ----------
// Phase 2에서 화면마다 안을 추가한다. 첫 항목이 기본.
const VARIANTS = {
  today: { 현행: renderToday },
  // 2026-09-26 확정: 기록 = 검색 먼저 + 즐겨찾기, 브랜드 = 영향 미리보기.
  record: { 확정: renderRecordSheet },
  brand: { 확정: renderBrandMenu },
  // 2026-09-26 확정: 밤 장면 + 당·카페인 분리 + 끌어서 주기.
  feeding: { 확정: renderFeeding },
  // 2026-09-26 확정: 캐주얼(캐릭터 카드·컵 선반·모은 방울·방울 달력).
  trends: { 확정: renderTrendsCasual },
  // 추이와 같은 캐주얼 문법으로 한 안만 만들었다(2026-09-26).
  settings: { 확정: renderSettings },
  // 2026-09-26 확정: 초상 + 말걸기(표정 칸 없음).
  affinity: { 확정: renderAffinity },
  paywall: { '미설계': () => renderSimpleSheet('슈가캡 PRO', '페이월은 Phase 2에서 다시 설계해요.') },
};
const variantName = screen => ui.variants[screen] ?? Object.keys(VARIANTS[screen])[0];
const pick = screen => VARIANTS[screen][variantName(screen)];

// ---------- 오늘 ----------
function renderToday() {
  const side = ui.side;
  const meta = SIDES[side];
  const today = dayKey(now());
  const t = totalsOf(today)[side];
  const limit = limitOf(side);
  setCup(cupAsset(meta.cupSet, cupStep(t.left, limit)));

  return `
    <div class="top-scrim"></div>
    <div class="headline" role="button" data-a="openDayLog" aria-label="오늘 기록 보기, "${meta.label} 남은 ${num(t.left)} ${meta.unit} / ${num(limit)} ${meta.unit}">
      <div class="date-label">${dateLabel(now())}</div>
      <div class="kicker">오늘 남은 ${meta.label}</div>
      <div class="number-row">
        <span class="hero-number">${num(t.left)}</span><span class="hero-unit">${meta.unit}</span>
        <span class="limit">/${num(limit)} ${meta.unit}</span>
      </div>
      ${t.over > 0 ? `<div class="overflow-note">+${num(t.over)} ${meta.unit} 넘김</div>` : ''}
    </div>
    <button class="heart-button" data-a="affinity" aria-label="호감도">${ICON.heart}</button>
    <div class="banners">${renderBanners(today)}</div>
    <div class="bottom-controls">
      ${renderCloseControl(today)}
      <span></span>
      <div class="page-dots">${SIDE_ORDER.map(s => `<i class="${s === side ? 'on' : ''}"></i>`).join('')}</div>
      <button class="fab" data-a="openRecord" aria-label="기록 추가">${ICON.plus}</button>
    </div>`;
}

function renderCloseControl(today) {
  if (S.days[today]?.closedAt) return `<span class="glass-pill quiet">${ICON.moon} 마감함</span>`;
  if (!isCloseWindowOpen()) return '<span></span>';
  return `<button class="glass-pill" data-a="closeToday">${ICON.moon} 오늘 마감</button>`;
}

function renderBanners(today) {
  const parts = [];
  const prompt = pendingPrompt();
  if (prompt?.kind === 'feed') {
    parts.push(`<div class="banner"><div class="banner-row"><span>어제 남은 음료를 먹여 주세요</span>
      <button class="glass-pill" style="background:var(--accent);color:#fff;border:0" data-a="feedYesterday" data-v="${prompt.day}">먹이기</button></div></div>`);
  } else if (prompt?.kind === 'ask') {
    parts.push(`<div class="banner">어제는 기록이 없어요. 음료를 안 마셨나요?
      <div class="banner-actions">
        <button class="glass-pill" style="background:var(--accent);color:#fff;border:0" data-a="noDrink" data-v="${prompt.day}">안 마셨어요</button>
        <button class="glass-pill" data-a="drank" data-v="${prompt.day}">마셨어요</button>
      </div></div>`);
  }
  if (ui.credit) {
    const ups = ui.credit.filter(r => r.after > r.before)
      .map(r => `<div class="accent">${SIDES[r.side].withGwa} ${stageName(r.after)}가 됐어요</div>`).join('');
    parts.push(`<div class="banner">지난밤 먹인 음료가 반영됐어요${ups}</div>`);
  }
  if (S.days[shiftDay(today, -1)]?.shrank) {
    parts.push('<div class="banner" style="color:var(--secondary)">어젯밤 이후 마신 만큼 빠졌어요</div>');
  }
  return parts.join('');
}

/** 컵 장면 크로스페이드(CupView: 0.35초). 매 렌더마다 이미지를 새로 만들지 않고, 바뀔 때만 겹쳐 갈아 끼운다. */
function setCup(src) {
  const layer = document.getElementById('cupBg');
  const current = layer.lastElementChild;
  if (current?.dataset.src === src) return;
  const img = new Image();
  img.src = src;
  img.dataset.src = src;
  img.alt = '';
  img.style.opacity = current ? '0' : '1';
  layer.appendChild(img);
  if (!current) return;
  requestAnimationFrame(() => requestAnimationFrame(() => { img.style.opacity = '1'; }));
  setTimeout(() => { while (layer.children.length > 1) layer.firstElementChild.remove(); }, 400);
}

// ---------- 기록 ----------
// 기록 시트·브랜드 메뉴·서빙 패널 안은 screens-record.js.

function renderManualSheet() {
  return `
    <div class="dim" data-a="closeSheet"></div>
    <div class="sheet">
      <div class="grabber"></div>
      <div class="sheet-head"><span class="kicker">직접 입력</span><button class="text-button" data-a="closeSheet">닫기</button></div>
      <div style="padding:8px 20px">
        <div class="field">이름<input id="mName" placeholder="음료 이름"></div>
        <div class="field">당(g)<input id="mSugar" inputmode="decimal" placeholder="모름"></div>
        <div class="field">카페인(mg)<input id="mCaffeine" inputmode="decimal" placeholder="모름"></div>
        <p style="font-size:13px;color:var(--secondary)">비워 두면 "미공개"로 남아요. 0으로 치지 않아요.</p>
        <button class="cta" data-a="saveManual" style="margin-top:12px">저장</button>
      </div>
    </div>`;
}

// ---------- 미설계 자리 ----------
function renderPlaceholder(title) {
  return `<div class="placeholder"><div class="date-label">${title}</div>
    <p style="margin-top:40px">이 화면은 Phase 2에서 메인 화면 문법(사진 전면 배경, 매거진 글자 위계, 유리 알약)으로 새로 설계해요.</p>
    <p>하루 기준·시각은 오른쪽 패널에서 바꿀 수 있어요.</p></div>`;
}
function renderSimpleSheet(kicker, text) {
  return `<div class="dim" data-a="closeSheet"></div><div class="sheet"><div class="grabber"></div>
    <div class="sheet-head"><span class="kicker">${kicker}</span><button class="text-button" data-a="closeSheet">닫기</button></div>
    <p style="padding:20px;color:var(--secondary);font-size:15px;line-height:1.5">${text}</p></div>`;
}

function renderTabbar() {
  const tabs = [['today', '오늘', ICON.cup], ['trends', '추이', ICON.chart], ['settings', '설정', ICON.gear]];
  return `<nav class="tabbar">${tabs.map(([id, label, icon]) =>
    `<button class="${ui.tab === id ? 'on' : ''}" data-a="tab" data-v="${id}">${icon}<span>${label}</span></button>`).join('')}</nav>`;
}

// ---------- 그리기 ----------
function render() {
  refreshSettlement();
  document.getElementById('statusTime').textContent = clockLabel(now());
  const base = document.getElementById('cupBg');
  base.style.display = ui.tab === 'today' ? '' : 'none';

  let html = '';
  if (ui.tab === 'today') html += `<div class="today">${pick('today')()}</div>`;
  else html += pick(ui.tab)();
  if (ui.pushed) html += pick('brand')();
  // 스크롤하는 탭은 내용이 상태 바 밑으로 들어가 글자가 겹친다. 배경색 띠로 옅게 가린다.
  if (ui.tab !== 'today') html += '<div class="top-fade"></div>';
  html += renderTabbar();
  if (ui.sheet === 'record') html += pick('record')();
  if (ui.sheet === 'manual') html += renderManualSheet();
  if (ui.sheet === 'daylog') html += renderDayLog();
  if (ui.sheet === 'affinity') html += pick('affinity')();
  if (ui.sheet === 'paywall') html += pick('paywall')();
  if (ui.sheet === 'goal') html += renderGoalSheet();
  if (ui.sheet === 'onboardingSoon') html += renderSimpleSheet('앱 소개', '온보딩은 다음 차례에 설계해요. 설계가 끝나면 여기서 다시 볼 수 있어요.');
  if (ui.sheet === 'restoreDone') html += renderSimpleSheet('구매 복원', '복원할 구매가 없어요. (프로토타입 흉내)');
  if (ui.stopGoalSide) html += renderStopGoal();
  if (ui.panelSheet) html += renderServingPanel();
  if (ui.cover) html += pick('feeding')();
  html += renderToast();
  html += isDraftVisible() ? '<span class="draft-tag">초안 · Phase 2</span>' : '';
  document.getElementById('layers').innerHTML = html;
  settleOverlays();
  document.getElementById('phone').classList.toggle('dark-status', Boolean(ui.cover));

  const search = document.getElementById('drinkSearch');
  if (search) search.oninput = () => { ui.query = search.value; renderKeepingFocus('drinkSearch'); };
  const globalSearch = document.getElementById('globalSearch');
  if (globalSearch) globalSearch.oninput = () => { ui.globalQuery = globalSearch.value; renderKeepingFocus('globalSearch'); };
  renderPanel();
  if (ui.tab === 'settings') afterRender.push(bindSettingsControls);
  // 방금 그린 DOM에 붙는 애니메이션·끌기 처리. 그리는 쪽이 필요할 때 넣는다.
  while (afterRender.length) afterRender.shift()();
}
const afterRender = [];

/**
 * 화면을 통째로 다시 그리기 때문에, 그냥 두면 시트·먹이기·밀어 넣기의 등장 애니메이션이
 * 버튼 하나 누를 때마다 다시 재생된다(컵이 자꾸 솟아오르던 문제). 새로 열린 층만 애니메이션하고
 * 이미 열려 있던 층은 멈춘 상태로 그린다.
 */
let lastOverlays = {};
function settleOverlays() {
  const current = {
    sheet: ui.sheet,
    panel: ui.panelSheet?.drinkId ?? null,
    pushed: ui.pushed?.brandId ?? null,
    cover: ui.cover ? `${ui.cover.kind}:${ui.cover.day}` : null,
  };
  const keep = (selector, key) => {
    if (current[key] && current[key] === lastOverlays[key]) {
      document.querySelectorAll(selector).forEach(el => el.classList.add('settled'));
    }
  };
  keep('.sheet', 'sheet');
  keep('.panel-sheet', 'panel');
  keep('.pushed', 'pushed');
  keep('.cover', 'cover');
  if (current.sheet === lastOverlays.sheet && current.panel === lastOverlays.panel) {
    document.querySelectorAll('.dim').forEach(el => el.classList.add('settled'));
  }
  lastOverlays = current;
}

/** 아직 안이 없는 초안 화면이 보이는 중인지. 안이 붙은 화면(기록·브랜드)은 표시하지 않는다. */
function isDraftVisible() {
  return Boolean(['manual', 'paywall', 'onboardingSoon'].includes(ui.sheet));
}

function renderKeepingFocus(id) {
  const pos = document.getElementById(id)?.selectionStart;
  const scroll = document.querySelector('.sheet .scroll, .pushed .scroll')?.scrollTop;
  render();
  const input = document.getElementById(id);
  if (input) { input.focus(); input.setSelectionRange(pos, pos); }
  const area = document.querySelector('.sheet .scroll, .pushed .scroll');
  if (area && scroll !== undefined) area.scrollTop = scroll;
}

// ---------- 동작 ----------
function record(entry) {
  const id = crypto.randomUUID();
  S.entries.push({ id, at: now(), quantity: 1, ...entry });
  saveState();
  return id;
}

/** 카탈로그 메뉴 한 잔(또는 여러 잔)을 기록한다. 최근 목록(다시 마시기)이 쓰도록 위치도 남긴다. */
function recordDrink(drinkId, servingIndex, variantIndex, quantity) {
  const drink = CATALOG.drinks.find(d => d.id === drinkId);
  if (!drink) throw new Error(`카탈로그에 없는 메뉴: ${drinkId}`);
  const serving = drink.servings[servingIndex];
  const variant = serving.caffeine_variants[variantIndex];
  const caffeine = variant ? variant.caffeine_mg : serving.caffeine_mg;
  const times = v => (v === null || v === undefined ? null : v * quantity);
  return record({
    drinkId, servingIndex, variantIndex,
    drinkName: drink.name,
    brandName: CATALOG.brands.find(b => b.id === drink.brand_id).name,
    sizeLabel: [TEMP[drink.temperature], serving.size_label === '기본' ? '' : serving.size_label, variant?.label].filter(Boolean).join(' '),
    quantity,
    sugarG: times(serving.sugar_g),
    caffeineMg: times(caffeine),
  });
}

let toastTimer = null;
function showToast(text, entryId) {
  ui.toast = { text, entryId };
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { ui.toast = null; render(); }, 4000);
}

const ACTIONS = {
  tab: v => { ui.tab = v; ui.pushed = null; },
  openRecord: () => { ui.sheet = 'record'; ui.globalQuery = ''; },
  openDayLog: v => { ui.sheet = 'daylog'; ui.dayLog = { key: v ?? dayKey(now()), editing: false }; },
  toggleEdit: () => { ui.dayLog.editing = !ui.dayLog.editing; },
  closeSheet: () => { ui.sheet = null; },
  brand: v => { ui.sheet = null; ui.pushed = { brandId: v }; ui.query = ''; ui.category = '전체'; },
  pop: () => { ui.pushed = null; },
  manual: () => { ui.sheet = 'manual'; },
  drink: v => { ui.panelSheet = { drinkId: v, size: 0, variant: 0, quantity: 1 }; },
  closePanel: () => { ui.panelSheet = null; },
  size: v => { ui.panelSheet.size = Number(v); ui.panelSheet.variant = 0; },
  variant: v => { ui.panelSheet.variant = Number(v); },
  qty: v => { ui.panelSheet.quantity = Math.max(1, ui.panelSheet.quantity + Number(v)); },
  addServing: () => {
    const p = ui.panelSheet;
    recordDrink(p.drinkId, p.size, p.variant, p.quantity);
    ui.panelSheet = null;
    // 기록하면 오늘로 돌아가 컵이 줄어드는 걸 본다(§4.2).
    ui.pushed = null;
    ui.sheet = null;
  },
  quickRecord: v => {
    const [drinkId, servingIndex, variantIndex] = v.split('|').map((x, i) => (i ? Number(x) : x));
    const id = recordDrink(drinkId, servingIndex, variantIndex, 1);
    ui.sheet = null;
    showToast(`${CATALOG.drinks.find(d => d.id === drinkId).name} 기록했어요`, id);
  },
  toggleFavorite: v => {
    S.favorites = isFavorite(v) ? S.favorites.filter(k => k !== v) : [...S.favorites, v];
    saveState();
  },
  undo: () => {
    S.entries = S.entries.filter(e => e.id !== ui.toast.entryId);
    saveState();
    ui.toast = null;
  },
  category: v => { ui.category = v; },
  saveManual: () => {
    const parse = id => {
      const raw = document.getElementById(id).value.trim();
      if (!raw) return null;
      const value = Number(raw);
      if (!Number.isFinite(value) || value < 0) throw new Error(`숫자가 아님: ${raw}`);
      return value;
    };
    const name = document.getElementById('mName').value.trim() || '직접 입력';
    try {
      record({ drinkName: name, brandName: '', sizeLabel: '직접 입력', sugarG: parse('mSugar'), caffeineMg: parse('mCaffeine') });
      ui.sheet = null;
    } catch (error) {
      alert(error.message);
    }
  },
  deleteEntry: v => { S.entries = S.entries.filter(e => e.id !== v); saveState(); },
  affinity: () => { ui.sheet = S.pro ? 'affinity' : 'paywall'; },
  closeToday: () => openFeeding('close', dayKey(now()), false),
  feedYesterday: v => openFeeding('past', v, false),
  noDrink: v => openFeeding('past', v, true),
  drank: v => { dayRow(v).asked = true; saveState(); },
  closeCover: () => { ui.cover = null; },
  // 먹이기 화면 안별 동작은 screens-feeding.js
  ...FEEDING_ACTIONS,
  ...AFFINITY_ACTIONS,
  ...TREND_ACTIONS,
  ...SETTINGS_ACTIONS,
};

/** 먹이기 화면을 연다. noDrink면 "안 마셨어요"라 가득 찬 컵으로 먹인다(§4.7). */
function openFeeding(kind, day, noDrink) {
  const t = totalsOf(day);
  ui.cover = {
    kind, day,
    left: noDrink ? { sugar: S.settings.sugarG, caffeine: S.settings.caffeineMg } : { sugar: t.sugar.left, caffeine: t.caffeine.left },
    over: noDrink ? { sugar: 0, caffeine: 0 } : { sugar: t.sugar.over, caffeine: t.caffeine.over },
    phase: 'ready',
    fedSides: [],
    results: null,
  };
}

/** 먹인 사실을 남긴다. 오늘 마감은 연출만 하고 적립은 하루 경계 뒤 첫 실행에(§9.5 Phase 2b), 지난 날은 바로 적립. */
function commitFeeding() {
  const c = ui.cover;
  const row = dayRow(c.day);
  row.closedAt = now();
  row.atClose = { ...c.left };
  if (c.kind === 'close') {
    c.results = [];
  } else {
    row.asked = true;
    c.results = credit(c.day, c.left);
  }
  saveState();
}

function handleClick(event) {
  const target = event.target.closest('[data-a]');
  if (!target) return;
  const action = ACTIONS[target.dataset.a];
  if (!action) throw new Error(`정의되지 않은 동작: ${target.dataset.a}`);
  action(target.dataset.v);
  render();
}

// 오늘 화면에서 좌우로 밀면 당 컵 ↔ 카페인 컵(§4.1).
function installSwipe(screen) {
  let start = null;
  screen.addEventListener('pointerdown', e => {
    if (ui.tab !== 'today' || ui.sheet || ui.pushed || ui.cover || ui.panelSheet) return;
    if (e.target.closest('button, .tabbar')) return;
    start = { x: e.clientX, y: e.clientY };
  });
  screen.addEventListener('pointerup', e => {
    if (!start) return;
    const dx = e.clientX - start.x, dy = e.clientY - start.y;
    start = null;
    if (Math.abs(dx) < 24 || Math.abs(dx) < Math.abs(dy)) return;
    ui.side = dx < 0 ? 'caffeine' : 'sugar';
    render();
  });
  document.addEventListener('keydown', e => {
    if (e.target.tagName === 'INPUT') return;
    if (e.key === 'ArrowLeft') { ui.side = 'sugar'; render(); }
    if (e.key === 'ArrowRight') { ui.side = 'caffeine'; render(); }
  });
}

// ---------- 오른쪽 조작 패널 ----------
function renderPanel() {
  const today = dayKey(now());
  const variantRows = Object.entries(VARIANTS).map(([screen, options]) => {
    const names = Object.keys(options);
    const current = ui.variants[screen] ?? names[0];
    return `<div class="row"><b style="width:64px">${screen}</b>${names.map(n =>
      `<button class="${n === current ? 'on' : ''}" data-p="variant" data-screen="${screen}" data-v="${esc(n)}">${esc(n)}</button>`).join('')}</div>`;
  }).join('');
  const affinityRows = SIDE_ORDER.map(side => {
    const char = SIDES[side].char;
    const p = S.points[char];
    return `<div class="muted">${SIDES[side].name}: ${p}점 · ${stageName(levelOf(p))}</div>`;
  }).join('');

  document.getElementById('panel').innerHTML = `
    <section><h3>시각 (앱 안 시계)</h3>
      <div class="row"><b>${dateLabel(now())} ${timeLabel(now())}</b></div>
      <div class="row"><button data-p="clock" data-v="-3600">−1시간</button><button data-p="clock" data-v="3600">+1시간</button><button data-p="clock" data-v="86400">+1일</button></div>
      <div class="row"><button data-p="evening">오늘 21시로</button><button data-p="realtime">실제 시각</button></div>
      <div class="muted">하루 키 ${today} · 마감 ${isCloseWindowOpen() ? '가능' : '불가(20시부터)'}</div>
    </section>
    <section><h3>상태</h3>
      <div class="row"><button class="${S.pro ? 'on' : ''}" data-p="pro">Pro ${S.pro ? '켜짐' : '꺼짐'}</button><button data-p="demo">데모 기록 넣기</button><button data-p="reset">초기화</button></div>
      <div class="row"><button data-p="history">지난 4주 데모</button><button data-p="goalWeek">줄이기 +1주 달성</button></div>
      <div class="row"><button data-p="points" data-v="30">호감도 +30점</button><button data-p="points" data-v="300">+300점</button></div>
      <div class="row"><label>당 기준 <input type="number" id="pSugar" value="${S.settings.sugarG}"> g</label></div>
      <div class="row"><label>카페인 기준 <input type="number" id="pCaffeine" value="${S.settings.caffeineMg}"> mg</label></div>
      ${affinityRows}
    </section>
    <section><h3>화면 안</h3>${variantRows}
      <div class="muted">Phase 2에서 화면마다 A·B·C 안이 여기 붙어요. 오늘 화면은 대표님 확정 디자인이라 현행 하나예요.</div>
    </section>
    <section><h3>조작</h3><div class="muted">컵 전환: 화면을 좌우로 끌기, 또는 키보드 ← →.<br>상태는 이 브라우저 localStorage에 저장돼요.</div></section>`;

  const bindNumber = (id, key) => {
    const input = document.getElementById(id);
    input.onchange = () => {
      const value = Number(input.value);
      if (!Number.isFinite(value) || value <= 0) { input.value = S.settings[key]; return; }
      S.settings[key] = value;
      saveState();
      render();
    };
  };
  bindNumber('pSugar', 'sugarG');
  bindNumber('pCaffeine', 'caffeineMg');
}

const PANEL_ACTIONS = {
  clock: (_, v) => { S.clockOffset += Number(v) * 1000; },
  evening: () => {
    const d = new Date(now());
    d.setHours(21, 0, 0, 0);
    S.clockOffset += d.getTime() - now();
  },
  realtime: () => { S.clockOffset = 0; },
  pro: () => { S.pro = !S.pro; },
  demo: () => {
    const t = now();
    S.entries.push(
      { id: crypto.randomUUID(), at: t - 90 * 60e3, quantity: 1, drinkName: 'ABC 클렌즈 190ML', brandName: '스타벅스', sizeLabel: 'Tall', sugarG: 16, caffeineMg: 0 },
      { id: crypto.randomUUID(), at: t - 30 * 60e3, quantity: 1, drinkName: '딸기 라떼', brandName: '메가MGC커피', sizeLabel: 'ICE', sugarG: 30, caffeineMg: 200 },
    );
  },
  reset: () => {
    if (!confirm('기록·호감도·시각을 모두 지울까요?')) return;
    S = freshState();
    ui.credit = null;
    ui.cover = ui.sheet = ui.pushed = ui.panelSheet = null;
  },
  variant: (el, v) => { ui.variants[el.dataset.screen] = v; },
  history: () => {
    // 지난 28일에 하루 1~3잔을 넣는다. 날마다 마감·확정된 것으로 표시해 어제 배너가 뜨지 않게 한다.
    const today = dayKey(now());
    let seed = 7;
    const rand = () => { seed = (seed * 1103515245 + 12345) >>> 0; return seed / 2 ** 32; };
    for (let back = 28; back >= 1; back -= 1) {
      const key = shiftDay(today, -back);
      const cups = 1 + Math.floor(rand() * 3);
      for (let i = 0; i < cups; i += 1) {
        S.entries.push({
          id: crypto.randomUUID(), at: new Date(`${key}T${pad(10 + i * 3)}:00:00`).getTime(), quantity: 1,
          drinkName: ['카페 라떼', '바닐라 라떼', '아메리카노', '딸기 라떼', '자몽 에이드'][Math.floor(rand() * 5)],
          brandName: '데모', sizeLabel: '', sugarG: Math.round(rand() * 32), caffeineMg: Math.round(rand() * 180),
        });
      }
      S.days[key] = { opened: true, closedAt: new Date(`${key}T22:00:00`).getTime(), atClose: { sugar: 0, caffeine: 0 }, finalized: true };
    }
    S.firstDay = shiftDay(today, -28);
  },
  goalWeek: () => {
    // 감소 목표가 도는 쪽을 한 주 달성시키고, 그 주 하루 기준을 설정에 써 넣는다(§9.5).
    for (const side of SIDE_ORDER) {
      const goal = S.goals?.[side];
      if (!goal) continue;
      goal.achieved = Math.min(goal.weeks, goal.achieved + 1);
      S.settings[SIDES[side].limitKey] = goalWeekLimit(goal, side);
    }
  },
  points: (_, v) => { for (const side of SIDE_ORDER) S.points[SIDES[side].char] += Number(v); },
};

document.getElementById('panel').addEventListener('click', event => {
  const el = event.target.closest('[data-p]');
  if (!el) return;
  PANEL_ACTIONS[el.dataset.p](el, el.dataset.v);
  saveState();
  render();
});

// ---------- 시작 ----------
async function start() {
  const screen = document.getElementById('screen');
  screen.innerHTML = '<div class="cup-bg" id="cupBg"></div><div id="layers"></div>';
  screen.addEventListener('click', handleClick);
  installSwipe(screen);

  // 컵 장면 18장을 미리 받아 둔다. 처음 줄어들 때 빈 화면이 끼지 않게.
  for (const side of SIDE_ORDER) for (const step of CUP_STEPS) new Image().src = cupAsset(SIDES[side].cupSet, step);

  render();
  const response = await fetch(CATALOG_URL);
  if (!response.ok) throw new Error(`카탈로그 로드 실패: ${CATALOG_URL} HTTP ${response.status}`);
  CATALOG = await response.json();
  if (CATALOG.schema_version !== 1) throw new Error(`지원하지 않는 schema_version: ${CATALOG.schema_version}`);
  render();
  setInterval(render, 60e3);
}

start();
