'use strict';
// Phase 2-1: 기록 시트·브랜드 메뉴 안(A·B·C). 메인 화면 문법을 잇는다:
// 컵 장면이 비치는 유리 바탕, 자간 벌린 소제목, 크기 대비로 만든 위계, 액센트는 주 동작 하나.
// app.js보다 먼저 읽힌다. 도우미(esc·num·ICON·S·ui 등)는 호출 시점에 app.js 전역에서 찾는다.

// ---------- 공통 조각 ----------
function todaysEntries() {
  const today = dayKey(now());
  return S.entries.filter(e => dayKey(e.at) === today).sort((a, b) => b.at - a.at);
}

/** 최근에 마신 음료(같은 메뉴·사이즈·원두는 한 번만). 카탈로그에서 온 기록만. */
function recentDrinks(limit) {
  const seen = new Set();
  const list = [];
  for (const e of [...S.entries].sort((a, b) => b.at - a.at)) {
    if (!e.drinkId) continue;
    const key = `${e.drinkId}|${e.servingIndex}|${e.variantIndex}`;
    if (seen.has(key)) continue;
    seen.add(key);
    list.push(e);
    if (list.length === limit) break;
  }
  return list;
}

const drinkCount = brandId => CATALOG.drinks.filter(d => d.brand_id === brandId).length;
const servingCaffeine = (serving, variantIndex) =>
  serving.caffeine_variants.length ? serving.caffeine_variants[variantIndex]?.caffeine_mg ?? serving.caffeine_mg : serving.caffeine_mg;

function sugarFigure(value) {
  if (value === null || value === undefined) return '<span class="figure-missing">미공개</span>';
  return `<b>${num(value)}</b><small>g</small>`;
}

function glassSheet(kicker, body, extraClass = '') {
  return `
    <div class="dim light" data-a="closeSheet"></div>
    <div class="sheet glass ${extraClass}">
      <div class="grabber"></div>
      <div class="sheet-head"><span class="kicker">${kicker}</span><button class="text-button" data-a="closeSheet">닫기</button></div>
      <div class="scroll">${body}</div>
    </div>`;
}

function todaySummaryRows() {
  const entries = todaysEntries();
  if (!entries.length) return '<div class="caption-note">아직 기록이 없어요. 컵은 가득 찬 채로 기다리고 있어요.</div>';
  return entries.map(e => {
    const title = e.quantity > 1 ? `${e.drinkName} ×${e.quantity}` : e.drinkName;
    const detail = [timeLabel(e.at), e.brandName, e.sizeLabel].filter(Boolean).join(' · ');
    return `<div class="log-row">
      <div class="log-text"><div class="log-name">${esc(title)}</div><div class="log-meta">${esc(detail)}</div></div>
      <div class="log-figure"><div>${sugarFigure(e.sugarG)}</div><div class="log-sub">${amount(e.caffeineMg, 'mg')}</div></div>
      <button class="log-del" data-a="deleteEntry" data-v="${e.id}" aria-label="삭제">×</button>
    </div>`;
  }).join('');
}

function todayCountKicker() {
  const n = todaysEntries().length;
  return n ? `오늘 기록 · ${n}잔` : '오늘 기록';
}

// ---------- 기록 시트 A: 매거진 ----------
function renderRecordA() {
  const brands = CATALOG?.brands ?? [];
  return glassSheet('기록', `
    <h2 class="sheet-headline">어디서<br>마셨나요</h2>
    <div class="index-list">
      ${brands.map(b => `<button class="index-row" data-a="brand" data-v="${b.id}">
        <span class="index-name">${esc(b.name)}</span><span class="index-count">${drinkCount(b.id)}</span></button>`).join('')}
    </div>
    <div class="pad-x"><button class="glass-pill" data-a="manual">＋ 직접 입력</button></div>
    <div class="kicker section-gap">${todayCountKicker()}</div>
    ${todaySummaryRows()}
    <div class="bottom-space"></div>`);
}

// ---------- 기록 시트 B: 다시 마시기 먼저 ----------
function renderRecordB() {
  const recents = recentDrinks(5);
  const brands = CATALOG?.brands ?? [];
  const recentRows = recents.length
    ? recents.map((e, i) => `<div class="again-row">
        <div class="log-text"><div class="log-name">${esc(e.drinkName)}</div>
          <div class="log-meta">${esc([e.brandName, e.sizeLabel].filter(Boolean).join(' · '))} · 당 ${amount(e.sugarG / e.quantity, 'g')}</div></div>
        <button class="again-add" data-a="again" data-v="${i}" aria-label="${esc(e.drinkName)} 한 잔 더">${ICON.plus}</button>
      </div>`).join('')
    : '<div class="caption-note">처음 기록하면 여기에 모여요. 다음부터는 한 번 눌러 기록해요.</div>';
  return glassSheet('기록', `
    <h2 class="sheet-headline">또 마셨나요</h2>
    <div class="kicker section-gap tight">다시 마시기</div>
    ${recentRows}
    <div class="kicker section-gap">다른 곳에서</div>
    <div class="pill-wrap">
      ${brands.map(b => `<button class="glass-pill" data-a="brand" data-v="${b.id}">${esc(b.name)}</button>`).join('')}
      <button class="glass-pill dashed" data-a="manual">＋ 직접 입력</button>
    </div>
    <div class="kicker section-gap">${todayCountKicker()}</div>
    ${todaySummaryRows()}
    <div class="bottom-space"></div>`);
}

// ---------- 기록 시트 C: 검색 먼저 ----------
function renderRecordC() {
  const q = ui.globalQuery.trim();
  let body;
  if (q && CATALOG) {
    const hits = CATALOG.drinks.filter(d => d.name.includes(q)).slice(0, 60);
    body = hits.length ? hits.map(d => {
      const s = d.servings[0];
      const brand = CATALOG.brands.find(b => b.id === d.brand_id).name;
      return `<button class="menu-row" data-a="drink" data-v="${esc(d.id)}">
        <div class="menu-text"><div class="menu-name">${esc(d.name)}</div><div class="menu-meta">${esc([brand, TEMP[d.temperature], s.size_label].filter(Boolean).join(' · '))}</div></div>
        <div class="menu-figure"><div>${sugarFigure(s.sugar_g)}</div><div class="log-sub">카페인 ${amount(servingCaffeine(s, 0), 'mg')}</div></div></button>`;
    }).join('') : `<div class="caption-note">"${esc(q)}" 메뉴가 없어요. 직접 입력으로 남길 수 있어요.</div>
      <div class="pad-x"><button class="glass-pill" data-a="manual">＋ 직접 입력</button></div>`;
  } else {
    const brands = CATALOG?.brands ?? [];
    body = `<div class="brand-grid">
        ${brands.map(b => `<button class="brand-card" data-a="brand" data-v="${b.id}">
          <span class="brand-card-name">${esc(b.name)}</span><span class="brand-card-count">메뉴 ${drinkCount(b.id)}</span></button>`).join('')}
        <button class="brand-card dashed" data-a="manual"><span class="brand-card-name">＋ 직접 입력</span><span class="brand-card-count">목록에 없을 때</span></button>
      </div>
      <div class="kicker section-gap">${todayCountKicker()}</div>
      ${todaySummaryRows()}`;
  }
  return glassSheet('기록', `
    <label class="big-search">${ICON.search}<input id="globalSearch" placeholder="메뉴 이름으로 찾기" value="${esc(ui.globalQuery)}" autocomplete="off"></label>
    ${q ? `<div class="kicker section-gap tight">8개 브랜드에서 찾은 메뉴</div>` : ''}
    ${body}
    <div class="bottom-space"></div>`);
}

// ---------- 브랜드 메뉴 공통 ----------
function brandHeader(brand) {
  return `
    <div class="nav-bar"><button class="back" data-a="pop">${ICON.back} 오늘</button></div>
    <div class="brand-head">
      <div class="kicker">${esc(brand.serving_note && brand.serving_note.length <= 20 ? brand.serving_note : `메뉴 ${drinkCount(brand.id)}`)}</div>
      <h1 class="brand-title">${esc(brand.name)}</h1>
    </div>`;
}

function filteredDrinks(brand) {
  const q = ui.query.trim();
  return CATALOG.drinks.filter(d =>
    d.brand_id === brand.id
    && (!q || d.name.includes(q))
    && (ui.category === '전체' || d.category === ui.category)
    && (ui.temperature === '전체' || d.temperature === 'both' || TEMP[d.temperature] === ui.temperature));
}

function categoryChips(brand) {
  const counts = {};
  for (const d of CATALOG.drinks) if (d.brand_id === brand.id) counts[d.category] = (counts[d.category] ?? 0) + 1;
  const names = ['전체', ...Object.keys(counts).sort((a, b) => counts[b] - counts[a])];
  return `<div class="chip-row">${names.map(n =>
    `<button class="chip ${ui.category === n ? 'on' : ''}" data-a="category" data-v="${esc(n)}">${esc(n)}</button>`).join('')}</div>`;
}

function brandSearch() {
  return `<label class="search">${ICON.search}<input id="drinkSearch" placeholder="메뉴 검색" value="${esc(ui.query)}" autocomplete="off"></label>`;
}

function menuRow(d) {
  const s = d.servings[0];
  return `<button class="menu-row" data-a="drink" data-v="${esc(d.id)}">
    <div class="menu-text"><div class="menu-name">${esc(d.name)}</div><div class="menu-meta">${esc([TEMP[d.temperature], s.size_label].filter(Boolean).join(' · '))}</div></div>
    <div class="menu-figure"><div>${sugarFigure(s.sugar_g)}</div><div class="log-sub">카페인 ${amount(servingCaffeine(s, 0), 'mg')}</div></div>
  </button>`;
}

// ---------- 브랜드 메뉴 A: 매거진 / B: 같은 목록 + 영향 미리보기 패널 ----------
function renderBrandA() {
  const brand = CATALOG.brands.find(b => b.id === ui.pushed.brandId);
  const drinks = filteredDrinks(brand);
  return `<div class="pushed">
    ${brandHeader(brand)}
    ${brandSearch()}
    ${categoryChips(brand)}
    <div class="scroll">${drinks.map(menuRow).join('') || '<div class="caption-note">맞는 메뉴가 없어요.</div>'}<div class="bottom-space"></div></div>
  </div>`;
}

// ---------- 브랜드 메뉴 C: 원탭 사이즈 ----------
function renderBrandC() {
  const brand = CATALOG.brands.find(b => b.id === ui.pushed.brandId);
  const drinks = filteredDrinks(brand);
  const temps = ['전체', 'ICE', 'HOT'];
  const rows = drinks.map(d => {
    const chips = d.servings.map((s, i) => {
      const label = d.servings.length === 1 ? `${s.size_label === '기본' ? '' : `${esc(s.size_label)} `}추가` : esc(s.size_label);
      return `<button class="size-chip" data-a="quickAdd" data-v="${esc(d.id)}|${i}">${label}<span>${s.sugar_g === null ? '—' : `${num(s.sugar_g)}g`}</span></button>`;
    }).join('');
    return `<div class="quick-row">
      <div class="menu-text"><div class="menu-name">${esc(d.name)}</div>
        <div class="menu-meta">${esc(TEMP[d.temperature] || 'HOT·ICE')} · 카페인 ${amount(servingCaffeine(d.servings[0], 0), 'mg')}</div></div>
      <div class="size-chips">${chips}</div>
    </div>`;
  }).join('');
  return `<div class="pushed">
    ${brandHeader(brand)}
    ${brandSearch()}
    <div class="segmented inset">${temps.map(t => `<button class="${ui.temperature === t ? 'on' : ''}" data-a="temperature" data-v="${t}">${t}</button>`).join('')}</div>
    ${categoryChips(brand)}
    <div class="scroll">${rows || '<div class="caption-note">맞는 메뉴가 없어요.</div>'}<div class="bottom-space"></div></div>
  </div>`;
}

// ---------- 서빙 패널 ----------
function servingState() {
  const p = ui.panelSheet;
  const drink = CATALOG.drinks.find(d => d.id === p.drinkId);
  const serving = drink.servings[p.size];
  const times = v => (v === null || v === undefined ? null : v * p.quantity);
  return { p, drink, serving, sugar: times(serving.sugar_g), caffeine: times(servingCaffeine(serving, p.variant)) };
}

function servingControls({ p, drink, serving }) {
  const variants = serving.caffeine_variants;
  return `
    ${drink.servings.length > 1 ? `<div class="segmented">${drink.servings.map((s, i) => `<button class="${i === p.size ? 'on' : ''}" data-a="size" data-v="${i}">${esc(s.size_label)}</button>`).join('')}</div>` : ''}
    ${variants.length ? `<div class="segmented">${variants.map((v, i) => `<button class="${i === p.variant ? 'on' : ''}" data-a="variant" data-v="${i}">${esc(v.label)}</button>`).join('')}</div>` : ''}`;
}

function panelFrame(inner) {
  return `<div class="dim light" data-a="closePanel" style="z-index:61"></div><div class="panel-sheet glass">${inner}</div>`;
}

/** A·C: 수치와 수량만. */
function renderServingPlain() {
  const st = servingState();
  const { p, drink } = st;
  return panelFrame(`
    <div class="panel-head"><div><div class="kicker">${esc(TEMP[drink.temperature] || '메뉴')}</div><div class="panel-title">${esc(drink.name)}</div></div>
      <button class="text-button" data-a="closePanel">닫기</button></div>
    ${servingControls(st)}
    <div class="panel-figures">
      <div><div class="figure-big">${st.sugar === null ? '—' : num(st.sugar)}<small>g</small></div><div class="log-sub">당</div></div>
      <div><div class="figure-big">${st.caffeine === null ? '—' : num(st.caffeine)}<small>mg</small></div><div class="log-sub">카페인</div></div>
      <div class="stepper"><button data-a="qty" data-v="-1">−</button><b>${p.quantity}</b><button data-a="qty" data-v="1">＋</button></div>
    </div>
    <button class="cta" data-a="addServing">추가</button>`);
}

/** B: 마시면 컵이 어떻게 되는지 먼저 보여 준다. */
function renderServingImpact() {
  const st = servingState();
  const { p, drink } = st;
  const t = totalsOf(dayKey(now()));
  const limit = limitOf('sugar');
  const beforeLeft = t.sugar.left;
  const afterUsed = t.sugar.used + (st.sugar ?? 0);
  const afterLeft = Math.max(0, limit - afterUsed);
  const afterOver = Math.max(0, afterUsed - limit);
  const cafAfter = Math.max(0, limitOf('caffeine') - t.caffeine.used - (st.caffeine ?? 0));
  const set = SIDES.sugar.cupSet;
  return panelFrame(`
    <div class="panel-head"><div><div class="kicker">${esc([TEMP[drink.temperature], st.serving.size_label].filter(Boolean).join(' · ') || '메뉴')}</div><div class="panel-title">${esc(drink.name)}</div></div>
      <button class="text-button" data-a="closePanel">닫기</button></div>
    ${servingControls(st)}
    <div class="impact">
      <div class="impact-cup" style="background-image:url('${cupAsset(set, cupStep(beforeLeft, limit))}')"></div>
      <div class="impact-mid">
        <div class="kicker">마시면 남는 당</div>
        <div class="impact-figure">${num(beforeLeft)}<span class="arrow">→</span>${num(afterLeft)}<small>g</small></div>
        <div class="log-sub">${st.sugar === null ? '당 미공개 메뉴라 컵은 그대로예요' : afterOver > 0 ? `하루 기준을 ${num(afterOver)} g 넘겨요` : `이 잔은 당 ${num(st.sugar)} g`}</div>
        <div class="log-sub">카페인은 ${num(cafAfter)} mg 남아요</div>
      </div>
      <div class="impact-cup" style="background-image:url('${cupAsset(set, cupStep(afterLeft, limit))}')"></div>
    </div>
    <div class="panel-foot">
      <div class="stepper"><button data-a="qty" data-v="-1">−</button><b>${p.quantity}</b><button data-a="qty" data-v="1">＋</button></div>
      <button class="cta grow" data-a="addServing">추가</button>
    </div>`);
}

function renderToast() {
  if (!ui.toast) return '';
  return `<div class="toast">${esc(ui.toast.text)}<button data-a="undo">되돌리기</button></div>`;
}
