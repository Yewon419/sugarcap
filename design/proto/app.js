'use strict';
// 슈가캡 HTML 프로토타입. 규칙은 SPEC §4.1·§4.7·§9.5를 따른다.
// 오늘 화면은 iOS 현행(대표님 확정 디자인)을 그대로 옮겼고, 나머지는 Phase 2에서 다시 설계한다.

const STORE_KEY = 'sugarcap-proto-v2';
const ASSETS = '../../SugarCap/Resources';
const CATALOG_URL = '../../data/catalog.json';

// ---------- 규칙 ----------
const SIDES = {
  sugar: { label: '당', unit: 'g', char: 'roshu', name: '로슈', withGwa: '로슈와', cupSet: 'strawberry-latte', limitKey: 'sugarG' },
  caffeine: { label: '카페인', unit: 'mg', char: 'kain', name: '카인', withGwa: '카인과', cupSet: 'iced-americano', limitKey: 'caffeineMg' },
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
  search: '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="6.8" cy="6.8" r="5"/><path d="m10.6 10.6 4 4" stroke-linecap="round"/></svg>',
};

// ---------- 화면 안(variant) 등록 ----------
// Phase 2에서 화면마다 안을 추가한다. 첫 항목이 기본.
const VARIANTS = {
  today: { 현행: renderToday },
  record: { 초안: renderRecordSheet },
  brand: { 초안: renderBrandMenu },
  feeding: { 초안: renderFeeding },
  trends: { '미설계': () => renderPlaceholder('추이') },
  settings: { '미설계': () => renderPlaceholder('설정') },
  affinity: { '미설계': () => renderSimpleSheet('호감도', '호감도 화면은 Phase 2에서 메인 화면 문법으로 다시 설계해요.') },
  paywall: { '미설계': () => renderSimpleSheet('슈가캡 PRO', '페이월은 Phase 2에서 다시 설계해요.') },
};
const pick = screen => {
  const options = VARIANTS[screen];
  return options[ui.variants[screen]] ?? Object.values(options)[0];
};

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
    <div class="headline" aria-label="${meta.label} 남은 ${num(t.left)} ${meta.unit} / ${num(limit)} ${meta.unit}">
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

// ---------- 기록(초안) ----------
function renderRecordSheet() {
  const today = dayKey(now());
  const todays = S.entries.filter(e => dayKey(e.at) === today).sort((a, b) => b.at - a.at);
  const brands = CATALOG ? CATALOG.brands : [];
  return `
    <div class="dim" data-a="closeSheet"></div>
    <div class="sheet">
      <div class="grabber"></div>
      <div class="sheet-head"><span class="kicker">기록</span><button class="text-button" data-a="closeSheet">닫기</button></div>
      <div class="scroll">
        <div class="section-kicker kicker">어디서 마셨나요</div>
        <div class="tiles">
          ${brands.map(b => `<button class="tile" data-a="brand" data-v="${b.id}">${esc(b.name)}</button>`).join('')}
          <button class="tile dashed" data-a="manual">＋ 직접 입력</button>
        </div>
        <div class="section-kicker kicker">오늘 기록</div>
        ${todays.length ? todays.map(renderEntry).join('') : '<div class="empty-note">첫 잔을 기록해 보세요</div>'}
      </div>
    </div>`;
}

function renderEntry(e) {
  const title = e.quantity > 1 ? `${e.drinkName} ×${e.quantity}` : e.drinkName;
  const detail = [timeLabel(e.at), e.brandName, e.sizeLabel].filter(Boolean).join(' · ');
  return `<div class="entry">
    <div><div class="title">${esc(title)}</div><div class="detail">${esc(detail)}</div></div>
    <div class="amounts">${amount(e.sugarG, 'g')} · ${amount(e.caffeineMg, 'mg')}</div>
    <button class="del" data-a="deleteEntry" data-v="${e.id}" aria-label="삭제">삭제</button>
  </div>`;
}

function renderBrandMenu() {
  const brand = CATALOG.brands.find(b => b.id === ui.pushed.brandId);
  const q = ui.query.trim();
  const drinks = CATALOG.drinks.filter(d => d.brand_id === brand.id && (!q || d.name.includes(q)));
  return `
    <div class="pushed">
      <div class="nav-bar"><button class="back" data-a="pop">${ICON.back} 오늘</button></div>
      <div class="nav-title">${esc(brand.name)}</div>
      <label class="search">${ICON.search}<input id="drinkSearch" placeholder="메뉴 검색" value="${esc(ui.query)}"></label>
      <div class="scroll">
        ${drinks.slice(0, 200).map(d => {
          const s = d.servings[0];
          return `<button class="drink" data-a="drink" data-v="${esc(d.id)}">
            <div><div class="name">${esc(d.name)}</div><div class="meta">${[TEMP[d.temperature], s.size_label].filter(Boolean).join(' · ')}</div></div>
            <div class="num">${amount(s.sugar_g, 'g')} · ${amount(s.caffeine_mg, 'mg')}</div></button>`;
        }).join('')}
        <div style="height:120px"></div>
      </div>
    </div>`;
}

function renderServingPanel() {
  const p = ui.panelSheet;
  const drink = CATALOG.drinks.find(d => d.id === p.drinkId);
  const serving = drink.servings[p.size];
  const variants = serving.caffeine_variants;
  const caffeine = variants.length ? variants[p.variant]?.caffeine_mg ?? serving.caffeine_mg : serving.caffeine_mg;
  const times = v => (v === null || v === undefined ? null : v * p.quantity);
  return `
    <div class="dim" data-a="closePanel" style="z-index:61"></div>
    <div class="panel-sheet">
      <div style="display:flex;justify-content:space-between;align-items:center">
        <div><div class="kicker">${esc(TEMP[drink.temperature] || '메뉴')}</div><div style="font-size:22px;font-weight:700;margin-top:6px">${esc(drink.name)}</div></div>
        <button class="text-button" data-a="closePanel">닫기</button>
      </div>
      ${drink.servings.length > 1 ? `<div class="segmented">${drink.servings.map((s, i) => `<button class="${i === p.size ? 'on' : ''}" data-a="size" data-v="${i}">${esc(s.size_label)}</button>`).join('')}</div>` : ''}
      ${variants.length ? `<div class="segmented">${variants.map((v, i) => `<button class="${i === p.variant ? 'on' : ''}" data-a="variant" data-v="${i}">${esc(v.label)}</button>`).join('')}</div>` : ''}
      <div style="display:flex;justify-content:space-between;align-items:center;margin:22px 0">
        <div style="font-size:15px;color:var(--secondary)">${amount(times(serving.sugar_g), 'g')} · ${amount(times(caffeine), 'mg')}</div>
        <div class="stepper"><button data-a="qty" data-v="-1">−</button><b>${p.quantity}</b><button data-a="qty" data-v="1">＋</button></div>
      </div>
      <button class="cta" data-a="addServing">추가</button>
    </div>`;
}

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

// ---------- 마감·먹이기(초안) ----------
function renderFeeding() {
  const c = ui.cover;
  const left = c.fed ? { sugar: 0, caffeine: 0 } : c.left;
  const bubble = side => {
    if (!c.fed) return '';
    const r = c.results?.find(x => x.side === side);
    const text = r && r.after > r.before ? `${stageName(r.after)}가 됐어요` : '잘 먹었어요';
    return `<div class="glass-pill" style="font-size:12px;height:28px;color:var(--accent)">${text}</div>`;
  };
  return `
    <div class="cover">
      <div class="cup-bg"><img src="${cupAsset(SIDES.sugar.cupSet, c.fed ? 0 : cupStep(c.left.sugar, limitOf('sugar')))}" alt=""></div>
      <div style="position:absolute;inset:0;background:linear-gradient(rgba(255,255,255,.96),rgba(255,255,255,.55) 45%,rgba(255,255,255,.2) 70%,rgba(255,255,255,.9))"></div>
      <button class="text-button" data-a="closeCover" style="position:absolute;right:20px;top:var(--safe-top)">닫기</button>
      <div class="headline">
        <div class="kicker" style="margin-top:44px">${c.kind === 'close' ? '오늘 마감' : '어제 남은 음료'}</div>
        <div class="number-row"><span class="hero-number">${num(left.sugar)}</span><span class="hero-unit">g</span></div>
        <div style="font-size:13px;color:var(--secondary);letter-spacing:.3px;line-height:1.5;margin-top:6px">
          ${c.fed ? '로슈가 먹었어요<br>카페인은 카인이 먹었어요' : `남은 당을 로슈에게<br>카페인 ${num(left.caffeine)} mg는 카인에게`}
        </div>
      </div>
      <div style="position:absolute;left:28px;right:28px;bottom:170px;display:flex;justify-content:space-between;align-items:flex-end">
        <div style="display:flex;flex-direction:column;align-items:center;gap:6px">${bubble('sugar')}<img src="${characterAsset('roshu')}" style="height:170px" alt="로슈"></div>
        <div style="display:flex;flex-direction:column;align-items:center;gap:6px;margin-bottom:24px">${bubble('caffeine')}<img src="${characterAsset('kain')}" style="height:110px" alt="카인"></div>
      </div>
      <div style="position:absolute;left:24px;right:24px;bottom:50px">
        <button class="cta" data-a="${c.fed ? 'closeCover' : 'feed'}">${c.fed ? '완료' : '먹이기'}</button>
        ${!c.fed && c.kind === 'close' ? '<p style="text-align:center;font-size:12px;color:var(--secondary);margin:12px 0 0">마감 뒤에 마신 음료도 오늘 몫으로 빠져요</p>' : ''}
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
  html += renderTabbar();
  if (ui.sheet === 'record') html += pick('record')();
  if (ui.sheet === 'manual') html += renderManualSheet();
  if (ui.sheet === 'affinity') html += pick('affinity')();
  if (ui.sheet === 'paywall') html += pick('paywall')();
  if (ui.panelSheet) html += renderServingPanel();
  if (ui.cover) html += pick('feeding')();
  html += isDraftVisible() ? '<span class="draft-tag">초안 · Phase 2</span>' : '';
  document.getElementById('layers').innerHTML = html;

  const search = document.getElementById('drinkSearch');
  if (search) {
    search.oninput = () => { ui.query = search.value; renderKeepingFocus(); };
  }
  renderPanel();
}

function isDraftVisible() {
  return Boolean(ui.sheet || ui.pushed || ui.cover || ui.tab !== 'today');
}

function renderKeepingFocus() {
  const pos = document.getElementById('drinkSearch')?.selectionStart;
  render();
  const input = document.getElementById('drinkSearch');
  if (input) { input.focus(); input.setSelectionRange(pos, pos); }
}

// ---------- 동작 ----------
function record(entry) {
  S.entries.push({ id: crypto.randomUUID(), at: now(), quantity: 1, ...entry });
  saveState();
}

const ACTIONS = {
  tab: v => { ui.tab = v; ui.pushed = null; },
  openRecord: () => { ui.sheet = 'record'; },
  closeSheet: () => { ui.sheet = null; },
  brand: v => { ui.sheet = null; ui.pushed = { brandId: v }; ui.query = ''; },
  pop: () => { ui.pushed = null; },
  manual: () => { ui.sheet = 'manual'; },
  drink: v => { ui.panelSheet = { drinkId: v, size: 0, variant: 0, quantity: 1 }; },
  closePanel: () => { ui.panelSheet = null; },
  size: v => { ui.panelSheet.size = Number(v); ui.panelSheet.variant = 0; },
  variant: v => { ui.panelSheet.variant = Number(v); },
  qty: v => { ui.panelSheet.quantity = Math.max(1, ui.panelSheet.quantity + Number(v)); },
  addServing: () => {
    const p = ui.panelSheet;
    const drink = CATALOG.drinks.find(d => d.id === p.drinkId);
    const serving = drink.servings[p.size];
    const variant = serving.caffeine_variants[p.variant];
    const caffeine = variant ? variant.caffeine_mg : serving.caffeine_mg;
    const times = v => (v === null || v === undefined ? null : v * p.quantity);
    record({
      drinkName: drink.name,
      brandName: CATALOG.brands.find(b => b.id === drink.brand_id).name,
      sizeLabel: [TEMP[drink.temperature], serving.size_label, variant?.label].filter(Boolean).join(' '),
      quantity: p.quantity,
      sugarG: times(serving.sugar_g),
      caffeineMg: times(caffeine),
    });
    ui.panelSheet = null;
    ui.pushed = null;
  },
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
  closeToday: () => {
    const t = totalsOf(dayKey(now()));
    ui.cover = { kind: 'close', day: dayKey(now()), left: { sugar: t.sugar.left, caffeine: t.caffeine.left }, fed: false };
  },
  feedYesterday: v => {
    const t = totalsOf(v);
    ui.cover = { kind: 'past', day: v, left: { sugar: t.sugar.left, caffeine: t.caffeine.left }, fed: false };
  },
  noDrink: v => {
    ui.cover = { kind: 'past', day: v, left: { sugar: S.settings.sugarG, caffeine: S.settings.caffeineMg }, fed: false };
  },
  drank: v => { dayRow(v).asked = true; saveState(); },
  feed: () => {
    const c = ui.cover;
    const row = dayRow(c.day);
    if (c.kind === 'close') {
      // 적립은 하루 경계가 지난 뒤 첫 실행에 최종 값으로 한다(§9.5 Phase 2b).
      row.closedAt = now();
      row.atClose = { ...c.left };
      c.results = [];
    } else {
      row.closedAt = now();
      row.atClose = { ...c.left };
      row.asked = true;
      c.results = credit(c.day, c.left);
    }
    c.fed = true;
    saveState();
  },
  closeCover: () => { ui.cover = null; },
};

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
