'use strict';
// 기록 시트·브랜드 메뉴(2026-09-26 대표님 확정). 메인 화면 문법을 잇는다:
// 컵 장면이 비치는 유리 바탕, 자간 벌린 소제목, 크기 대비로 만든 위계, 액센트는 주 동작 하나.
//  - 기록 시트 = 검색 먼저 + 즐겨찾기(별표한 음료 → 최근 마신 음료) + 브랜드 격자. 오늘 기록 목록은 뺐다.
//  - 브랜드 메뉴 = 분류 칩 목록 + 영향 미리보기 패널(마시면 남는 당, 컵 전후).
// app.js보다 먼저 읽힌다. 도우미(esc·num·ICON·S·ui 등)는 호출 시점에 app.js 전역에서 찾는다.

// ---------- 공통 조각 ----------
const drinkKey = (drinkId, servingIndex, variantIndex) => `${drinkId}|${servingIndex}|${variantIndex}`;
const isFavorite = key => S.favorites.includes(key);
const drinkCount = brandId => CATALOG.drinks.filter(d => d.brand_id === brandId).length;
const servingCaffeine = (serving, variantIndex) =>
  serving.caffeine_variants.length ? serving.caffeine_variants[variantIndex]?.caffeine_mg ?? serving.caffeine_mg : serving.caffeine_mg;

/** 즐겨찾기 키 하나를 화면에 쓸 정보로. 카탈로그가 바뀌어 사라진 메뉴면 null. */
function describeDrink(key) {
  const [drinkId, servingIndex, variantIndex] = key.split('|');
  const drink = CATALOG.drinks.find(d => d.id === drinkId);
  const serving = drink?.servings[Number(servingIndex)];
  if (!serving) return null;
  const variant = serving.caffeine_variants[Number(variantIndex)];
  return {
    key,
    name: drink.name,
    meta: [
      CATALOG.brands.find(b => b.id === drink.brand_id).name,
      TEMP[drink.temperature],
      serving.size_label === '기본' ? '' : serving.size_label,
      variant?.label,
    ].filter(Boolean).join(' · '),
    sugar: serving.sugar_g,
  };
}

/** 별표한 음료가 먼저, 그 아래 최근 마신 음료(별표와 겹치지 않게 최대 5개). */
function favoriteList() {
  const favorites = S.favorites.map(describeDrink).filter(Boolean);
  const recents = [];
  const seen = new Set(S.favorites);
  for (const e of [...S.entries].sort((a, b) => b.at - a.at)) {
    if (!e.drinkId) continue;
    const key = drinkKey(e.drinkId, e.servingIndex, e.variantIndex);
    if (seen.has(key)) continue;
    seen.add(key);
    const info = describeDrink(key);
    if (info) recents.push(info);
    if (recents.length === 5) break;
  }
  return { favorites, recents };
}

function sugarFigure(value) {
  if (value === null || value === undefined) return '<span class="figure-missing">미공개</span>';
  return `<b>${num(value)}</b><small>g</small>`;
}

function starButton(key) {
  const on = isFavorite(key);
  return `<button class="star ${on ? 'on' : ''}" data-a="toggleFavorite" data-v="${esc(key)}" aria-label="${on ? '즐겨찾기 해제' : '즐겨찾기'}" aria-pressed="${on}">${on ? ICON.starFill : ICON.star}</button>`;
}

function glassSheet(kicker, body) {
  return `
    <div class="dim light" data-a="closeSheet"></div>
    <div class="sheet glass">
      <div class="grabber"></div>
      <div class="sheet-head"><span class="kicker">${kicker}</span><button class="text-button" data-a="closeSheet">닫기</button></div>
      <div class="scroll">${body}</div>
    </div>`;
}

// ---------- 기록 시트 ----------
function renderRecordSheet() {
  const q = ui.globalQuery.trim();
  return glassSheet('기록', `
    <label class="big-search">${ICON.search}<input id="globalSearch" placeholder="메뉴 이름으로 찾기" value="${esc(ui.globalQuery)}" autocomplete="off"></label>
    ${q && CATALOG ? searchResults(q) : `${favoriteSection()}${brandGrid()}`}
    <div class="bottom-space"></div>`);
}

function favoriteSection() {
  if (!CATALOG) return '';
  const { favorites, recents } = favoriteList();
  const row = info => `<div class="again-row">
      ${starButton(info.key)}
      <div class="log-text"><div class="log-name">${esc(info.name)}</div>
        <div class="log-meta">${esc(info.meta)} · 당 ${amount(info.sugar, 'g')}</div></div>
      <button class="again-add" data-a="quickRecord" data-v="${esc(info.key)}" aria-label="${esc(info.name)} 기록">${ICON.plus}</button>
    </div>`;
  const body = favorites.length || recents.length
    ? `${favorites.map(row).join('')}
       ${recents.length ? `${favorites.length ? '<div class="sub-kicker">최근 마신 음료</div>' : ''}${recents.map(row).join('')}` : ''}`
    : '<div class="caption-note">자주 마시는 음료는 별을 눌러 두세요. 최근 마신 음료도 여기 모여요. 한 번 눌러 바로 기록해요.</div>';
  return `<div class="kicker section-gap tight">즐겨찾기</div>${body}`;
}

function brandGrid() {
  const brands = CATALOG?.brands ?? [];
  return `<div class="kicker section-gap">브랜드</div>
    <div class="brand-grid">
      ${brands.map(b => `<button class="brand-card" data-a="brand" data-v="${b.id}">
        <span class="brand-card-name">${esc(b.name)}</span><span class="brand-card-count">메뉴 ${drinkCount(b.id)}</span></button>`).join('')}
      <button class="brand-card dashed" data-a="manual"><span class="brand-card-name">＋ 직접 입력</span><span class="brand-card-count">목록에 없을 때</span></button>
    </div>`;
}

function searchResults(q) {
  const hits = CATALOG.drinks.filter(d => d.name.includes(q)).slice(0, 60);
  if (!hits.length) {
    return `<div class="caption-note" style="padding-top:18px">"${esc(q)}" 메뉴가 없어요. 직접 입력으로 남길 수 있어요.</div>
      <div class="pad-x"><button class="glass-pill" data-a="manual">＋ 직접 입력</button></div>`;
  }
  return `<div class="kicker section-gap tight">8개 브랜드에서 찾은 메뉴</div>${hits.map(d => {
    const s = d.servings[0];
    const brand = CATALOG.brands.find(b => b.id === d.brand_id).name;
    return `<button class="menu-row" data-a="drink" data-v="${esc(d.id)}">
      <div class="menu-text"><div class="menu-name">${esc(d.name)}</div><div class="menu-meta">${esc([brand, TEMP[d.temperature], s.size_label].filter(Boolean).join(' · '))}</div></div>
      <div class="menu-figure"><div>${sugarFigure(s.sugar_g)}</div><div class="log-sub">카페인 ${amount(servingCaffeine(s, 0), 'mg')}</div></div></button>`;
  }).join('')}`;
}

// ---------- 브랜드 메뉴 ----------
function renderBrandMenu() {
  const brand = CATALOG.brands.find(b => b.id === ui.pushed.brandId);
  const drinks = filteredDrinks(brand);
  return `<div class="pushed">
    <div class="nav-bar"><button class="back" data-a="pop">${ICON.back} 오늘</button></div>
    <div class="brand-head">
      <div class="kicker">${esc(brand.serving_note && brand.serving_note.length <= 20 ? brand.serving_note : `메뉴 ${drinkCount(brand.id)}`)}</div>
      <h1 class="brand-title">${esc(brand.name)}</h1>
    </div>
    <label class="search">${ICON.search}<input id="drinkSearch" placeholder="메뉴 검색" value="${esc(ui.query)}" autocomplete="off"></label>
    ${categoryChips(brand)}
    <div class="scroll">${drinks.map(menuRow).join('') || '<div class="caption-note">맞는 메뉴가 없어요.</div>'}<div class="bottom-space"></div></div>
  </div>`;
}

function filteredDrinks(brand) {
  const q = ui.query.trim();
  return CATALOG.drinks.filter(d =>
    d.brand_id === brand.id && (!q || d.name.includes(q)) && (ui.category === '전체' || d.category === ui.category));
}

function categoryChips(brand) {
  const counts = {};
  for (const d of CATALOG.drinks) if (d.brand_id === brand.id) counts[d.category] = (counts[d.category] ?? 0) + 1;
  const names = ['전체', ...Object.keys(counts).sort((a, b) => counts[b] - counts[a])];
  return `<div class="chip-row">${names.map(n =>
    `<button class="chip ${ui.category === n ? 'on' : ''}" data-a="category" data-v="${esc(n)}">${esc(n)}</button>`).join('')}</div>`;
}

function menuRow(d) {
  const s = d.servings[0];
  return `<button class="menu-row" data-a="drink" data-v="${esc(d.id)}">
    <div class="menu-text"><div class="menu-name">${esc(d.name)}</div><div class="menu-meta">${esc([TEMP[d.temperature], s.size_label].filter(Boolean).join(' · '))}</div></div>
    <div class="menu-figure"><div>${sugarFigure(s.sugar_g)}</div><div class="log-sub">카페인 ${amount(servingCaffeine(s, 0), 'mg')}</div></div>
  </button>`;
}

// ---------- 영향 미리보기 패널 ----------
function renderServingPanel() {
  const p = ui.panelSheet;
  const drink = CATALOG.drinks.find(d => d.id === p.drinkId);
  const serving = drink.servings[p.size];
  const variants = serving.caffeine_variants;
  const times = v => (v === null || v === undefined ? null : v * p.quantity);
  const sugar = times(serving.sugar_g);
  const caffeine = times(servingCaffeine(serving, p.variant));

  const t = totalsOf(dayKey(now()));
  const limit = limitOf('sugar');
  const beforeLeft = t.sugar.left;
  const afterUsed = t.sugar.used + (sugar ?? 0);
  const afterLeft = Math.max(0, limit - afterUsed);
  const afterOver = Math.max(0, afterUsed - limit);
  const caffeineAfter = Math.max(0, limitOf('caffeine') - t.caffeine.used - (caffeine ?? 0));
  const set = SIDES.sugar.cupSet;
  const note = sugar === null ? '당 미공개 메뉴라 컵은 그대로예요'
    : afterOver > 0 ? `하루 기준을 ${num(afterOver)} g 넘겨요` : `이 잔은 당 ${num(sugar)} g`;

  return `<div class="dim light" data-a="closePanel" style="z-index:61"></div><div class="panel-sheet glass">
    <div class="panel-head">
      <div><div class="kicker">${esc([TEMP[drink.temperature], serving.size_label === '기본' ? '' : serving.size_label].filter(Boolean).join(' · ') || '메뉴')}</div>
        <div class="panel-title">${esc(drink.name)}</div></div>
      <div class="panel-head-actions">${starButton(drinkKey(drink.id, p.size, p.variant))}<button class="text-button" data-a="closePanel">닫기</button></div>
    </div>
    ${drink.servings.length > 1 ? `<div class="segmented">${drink.servings.map((s, i) => `<button class="${i === p.size ? 'on' : ''}" data-a="size" data-v="${i}">${esc(s.size_label)}</button>`).join('')}</div>` : ''}
    ${variants.length ? `<div class="segmented">${variants.map((v, i) => `<button class="${i === p.variant ? 'on' : ''}" data-a="variant" data-v="${i}">${esc(v.label)}</button>`).join('')}</div>` : ''}
    <div class="impact">
      <div class="impact-cup" style="background-image:url('${cupAsset(set, cupStep(beforeLeft, limit))}')"></div>
      <div class="impact-mid">
        <div class="kicker">마시면 남는 당</div>
        <div class="impact-figure">${num(beforeLeft)}<span class="arrow">→</span>${num(afterLeft)}<small>g</small></div>
        <div class="log-sub">${note}</div>
        <div class="log-sub">카페인은 ${num(caffeineAfter)} mg 남아요</div>
      </div>
      <div class="impact-cup" style="background-image:url('${cupAsset(set, cupStep(afterLeft, limit))}')"></div>
    </div>
    <div class="panel-foot">
      <div class="stepper"><button data-a="qty" data-v="-1">−</button><b>${p.quantity}</b><button data-a="qty" data-v="1">＋</button></div>
      <button class="cta grow" data-a="addServing">추가</button>
    </div>
  </div>`;
}

function renderToast() {
  if (!ui.toast) return '';
  return `<div class="toast">${esc(ui.toast.text)}<button data-a="undo">되돌리기</button></div>`;
}

// ---------- 하루 기록 시트(오늘 숫자를 누르면 열림, 추이에서도 같은 시트) ----------
// 기록 시트에서 오늘 기록 목록을 뺀 대신 여기서 보고 지운다(2026-09-26 대표님 결정).
function renderDayLog() {
  const key = ui.dayLog.key;
  const isToday = key === dayKey(now());
  const entries = S.entries.filter(e => dayKey(e.at) === key).sort((a, b) => b.at - a.at);
  const t = totalsOf(key);
  const d = new Date(`${key}T12:00:00`);
  const title = isToday ? '오늘 기록' : `${d.getMonth() + 1}월 ${d.getDate()}일 기록`;
  const editing = ui.dayLog.editing;
  const figure = (value, unit, label, limit) => `<div class="day-figure">
      <div class="day-figure-num">${num(value)}<small>${unit}</small></div>
      <div class="log-sub">${label} · 기준 ${num(limit)} ${unit}</div></div>`;
  const rows = entries.map(e => {
    const name = e.quantity > 1 ? `${e.drinkName} ×${e.quantity}` : e.drinkName;
    const meta = [timeLabel(e.at), e.brandName, e.sizeLabel].filter(Boolean).join(' · ');
    return `<div class="again-row">
      ${editing ? `<button class="minus-circle" data-a="deleteEntry" data-v="${e.id}" aria-label="${esc(name)} 삭제">−</button>` : ''}
      <div class="log-text"><div class="log-name">${esc(name)}</div><div class="log-meta">${esc(meta)}</div></div>
      <div class="log-figure"><div>${sugarFigure(e.sugarG)}</div><div class="log-sub">${amount(e.caffeineMg, 'mg')}</div></div>
    </div>`;
  }).join('');
  return `
    <div class="dim light" data-a="closeSheet"></div>
    <div class="sheet glass">
      <div class="grabber"></div>
      <div class="sheet-head"><span class="kicker">${title}${entries.length ? ` · ${entries.length}잔` : ''}</span>
        <span>${entries.length ? `<button class="text-button" data-a="toggleEdit">${editing ? '완료' : '편집'}</button>` : ''}<button class="text-button" data-a="closeSheet">닫기</button></span></div>
      <div class="scroll">
        <div class="day-figures">${figure(t.sugar.used, 'g', '당', limitOf('sugar'))}${figure(t.caffeine.used, 'mg', '카페인', limitOf('caffeine'))}</div>
        ${rows || `<div class="caption-note">${isToday ? '아직 기록이 없어요. 컵은 가득 찬 채로 기다리고 있어요.' : '이날은 기록이 없어요.'}</div>`}
        ${editing ? '<div class="caption-note" style="padding-top:14px">지운 음료만큼 컵이 다시 차요.</div>' : ''}
        <div class="bottom-space"></div>
      </div>
    </div>`;
}
