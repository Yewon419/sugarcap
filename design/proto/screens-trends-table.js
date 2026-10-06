'use strict';
// 추이 A안 "식탁 위 일주일"(2026-10-04). 대표님: 현행 캐주얼이 "AI 디자인스럽고 별로 캐주얼하지 않다".
// v2: 딸기색 무대는 "촌스럽다"(대표님) → 오늘 탭과 같은 사진 세계(벽 #F3F5F8 + 식탁)를 한 발 물러서 본 장면.
// v3: "버튼과 글자가 너무 많다, 척 보고 알아야 한다"(대표님) → 화면 글자는 기간·큰 숫자·잔 숫자·요일뿐.
//  - 당↔카페인: 오늘 탭처럼 옆으로 밀기 + 점 두 개(버튼 없음).
//  - 주↔월: "이번 주" 라벨을 누르면 고르는 메뉴(앱에선 SwiftUI Menu). 월은 Pro.
//  - 설명 줄·잠긴 비교 카드 삭제. 지난주 비교는 Pro일 때만 큰 숫자 아래 한 줄.
// 주 = 하루 한 잔, 월 = 한 주 한 잔(SPEC 9-7: 월 보기는 주별 하루 평균).

const TABLE_CUP_CROP = { x: 199, y: 426, w: 538, h: 1022, imgW: 937 };

const tableNum = v => Math.round(v).toLocaleString('ko-KR');

const tableCupAsset = (set, step) => `../assets/cups/cutouts/cutout-${set}-${step}.png`;

function tableGlass(set, step, width, dim) {
  const scale = width / TABLE_CUP_CROP.w;
  const height = Math.round(TABLE_CUP_CROP.h * scale);
  return `<span class="table-glass ${dim ? 'faded' : ''}" style="width:${width}px;height:${height}px">
    <img src="${tableCupAsset(set, step)}" alt="" style="width:${Math.round(TABLE_CUP_CROP.imgW * scale)}px;left:${-Math.round(TABLE_CUP_CROP.x * scale)}px;top:${-Math.round(TABLE_CUP_CROP.y * scale)}px">
  </span>`;
}

/** 잔 아래 숫자: 남긴 양, 넘겼으면 +넘긴 양(색), 기록 없으면 -. 단위는 큰 숫자에만 붙인다. */
function tableAmount(recorded, rest, over) {
  if (!recorded) return '<span class="table-amount none">-</span>';
  if (over > 0) return `<span class="table-amount over">+${tableNum(over)}</span>`;
  return `<span class="table-amount">${tableNum(rest)}</span>`;
}

/** 날짜 범위 "9.28 – 10.4". 지면 머리 오른쪽에 둔다. */
function tableDates(first, last) {
  const f = k => { const d = dayLabel(k).date; return `${d.getMonth() + 1}.${d.getDate()}`; };
  return `${f(first)} – ${f(last)}`;
}

// 매거진 지면처럼: 머리(기간·날짜) + 검은 가는 선 → 제목(2026-10-06 대표님: "로슈한테" 빼고 "남긴 당"만) → 아래쪽에 큰 숫자(단위는 어깨 위) → 가는 선 + 한 줄.
// 숫자는 자리 수가 늘면 줄여서 한 줄에 둔다.
function tableShell({ side, meta, period, dates, total, note, row, at, n }) {
  const range = trendRange();
  const other = range === 'week' ? 'month' : 'week';
  const digits = tableNum(total).length;
  return `<div class="trends table ${side}">
    <div class="table-title">
      <div class="table-mast">
        <button class="table-period" data-a="trendRange" data-v="${other}" aria-label="기간 바꾸기, 지금 ${period}">${period} <span class="chev" aria-hidden="true"></span></button>
        <span class="table-dates">${dates}</span>
      </div>
      <h2 class="table-head">남긴 ${meta.label}</h2>
      <div class="table-figure" style="--fs:${digits <= 2 ? 150 : digits === 3 ? 124 : digits <= 5 ? 100 : 80}px">
        <span class="table-number">${tableNum(total)}</span><span class="table-unit">${meta.unit}</span>
      </div>
      <div class="table-deck">
        ${note ? `<p>${note}</p>` : ''}
        ${tableLimitLink(side, meta)}
      </div>
    </div>
    <div class="table-scene">
      <div class="table-wall" style="--at:${at};--n:${n}"><img class="table-char ${at < n / 2 ? 'from-left' : ''}" src="${characterAsset(meta.char)}" alt="${meta.name}"></div>
      <div class="table-top">
        ${row}
        <div class="table-dots">${SIDE_ORDER.map(s =>
          `<button class="${s === side ? 'on' : ''}" data-a="trendSide" data-v="${s}" aria-label="${SIDES[s].label}"></button>`).join('')}</div>
      </div>
    </div>
  </div>`;
}

/** 하루 기준(2026-10-05 설정에서 추이로 옮김). 큰 숫자가 이 기준에서 남긴 양이라 그 바로 아래 지면 끝줄에 둔다.
 *  누르면 앱의 하루 기준 화면(컵 끌기·칩·조금씩 줄이기)으로 간다. 프로토에선 화면을 따로 그리지 않았다. */
function tableLimitLink(side, meta) {
  const goal = goalOf(side);
  return `<button class="table-limit" aria-label="${meta.label} 하루 기준 ${num(limitOf(side))} ${meta.unit}${goal ? ', 줄이는 중' : ''}">
    <span>${goal ? '줄이는 중' : '하루 기준'}</span><b>${tableNum(limitOf(side))} ${meta.unit}</b><span class="chev" aria-hidden="true"></span>
  </button>`;
}

function renderTrendsTable() {
  const side = trendSide();
  const meta = SIDES[side];
  const limit = limitOf(side);
  const todayKey = dayKey(now());
  if (trendRange() === 'month') return renderTableMonth(side, meta, limit, todayKey);

  const w = weekStats(side);
  // 기록 없는 지난날은 "남겼다"고 셀 수 없다(안 적었을 수도 있다). 기록한 날과 오늘만 센다.
  const counted = w.days.filter(k => hasEntries(k) || k === todayKey);
  const total = counted.reduce((sum, k) => sum + Math.max(0, limit - usedOn(k, side)), 0);

  const cups = w.days.map(key => {
    const used = usedOn(key, side);
    const recorded = hasEntries(key) || key === todayKey;
    const rest = Math.max(0, limit - used);
    const over = used - limit;
    const { wd } = dayLabel(key);
    return `<button class="table-cup ${key === todayKey ? 'is-today' : ''}" data-a="openDayLog" data-v="${key}"
      aria-label="${wd}요일 ${recorded ? (over > 0 ? `기준보다 ${num(over)} ${meta.unit} 더 마심` : `남은 ${meta.label} ${num(rest)} ${meta.unit}`) : '기록 없음'}">
      ${tableGlass(meta.cupSet, recorded ? cupStep(rest, limit) : 0, 50, !recorded)}
      ${tableAmount(recorded, rest, over)}
      <span class="table-day">${key === todayKey ? '오늘' : wd}</span>
    </button>`;
  }).join('');

  return tableShell({ side, meta, period: '이번 주', total, note: tableCompare(side), dates: tableDates(w.days[0], w.days[6]), row: `<div class="table-row week">${cups}</div>`, at: w.days.indexOf(todayKey), n: 7 });
}

/** 큰 숫자와 같은 셈: 기록한 날과 오늘만 남긴 양을 더한다. */
function tableRestTotal(days, side) {
  const limit = limitOf(side);
  const todayKey = dayKey(now());
  return days.filter(k => hasEntries(k) || k === todayKey)
    .reduce((sum, k) => sum + Math.max(0, limit - usedOn(k, side)), 0);
}

/** 지난주 대비는 Pro만, 큰 숫자 아래 한 줄. 큰 숫자가 "남긴 양"이라 비교도 남긴 양으로 한다. */
function tableCompare(side) {
  if (!S.pro) return '';
  const meta = SIDES[side];
  const cur = tableRestTotal(weekStats(side).days, side);
  const prevDays = weekStats(side, 7).days;
  if (!prevDays.some(hasEntries)) return '';
  const diff = cur - tableRestTotal(prevDays, side);
  if (Math.round(diff) === 0) return '지난주만큼 남겼어요';
  return `지난주보다 <b>${tableNum(Math.abs(diff))}${meta.unit} ${diff > 0 ? '더' : '덜'}</b> 남겼어요`;
}

/** 월(Pro): 이번 달 주마다 한 잔. 잔 = 그 주 하루 평균으로 남긴 양. */
function renderTableMonth(side, meta, limit, todayKey) {
  const today = new Date(now());
  const first = new Date(today.getFullYear(), today.getMonth(), 1);
  const days = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();
  const keys = Array.from({ length: days }, (_, i) => `${first.getFullYear()}-${pad(first.getMonth() + 1)}-${pad(i + 1)}`);
  const weeks = [];
  keys.forEach((k, i) => {
    const idx = Math.floor((i + first.getDay()) / 7);
    (weeks[idx] ??= []).push(k);
  });
  const countedAll = keys.filter(k => k <= todayKey && (hasEntries(k) || k === todayKey));
  const total = countedAll.reduce((s, k) => s + Math.max(0, limit - usedOn(k, side)), 0);

  const cups = weeks.map((ks, i) => {
    const counted = ks.filter(k => k <= todayKey && (hasEntries(k) || k === todayKey));
    const future = ks[0] > todayKey;
    const avgUsed = counted.length ? counted.reduce((s, k) => s + usedOn(k, side), 0) / counted.length : 0;
    const rest = Math.max(0, limit - avgUsed);
    const over = avgUsed - limit;
    return `<div class="table-cup ${ks.includes(todayKey) ? 'is-today' : ''}" aria-label="${i + 1}주차 ${counted.length ? `하루 평균 남은 ${num(rest)} ${meta.unit}` : '기록 없음'}">
      ${tableGlass(meta.cupSet, counted.length ? cupStep(rest, limit) : 0, 58, !counted.length || future)}
      ${tableAmount(counted.length > 0, rest, over)}
      <span class="table-day">${i + 1}주</span>
    </div>`;
  }).join('');

  return tableShell({ side, meta, period: `${today.getMonth() + 1}월`, total, note: '', dates: tableDates(keys[0], keys[keys.length - 1]), row: `<div class="table-row month" style="--n:${weeks.length}">${cups}</div>`, at: weeks.findIndex(ks => ks.includes(todayKey)), n: weeks.length });
}

// 당↔카페인은 오늘 탭처럼 옆으로 밀어서 바꾼다. 밀면 해당 점을 누른 것과 같다.
(() => {
  let start = null;
  document.addEventListener('pointerdown', e => {
    start = e.target.closest('.trends.table') ? { x: e.clientX, y: e.clientY } : null;
  });
  document.addEventListener('pointerup', e => {
    if (!start) return;
    const dx = e.clientX - start.x;
    const dy = e.clientY - start.y;
    start = null;
    if (Math.abs(dx) < 50 || Math.abs(dx) < Math.abs(dy)) return;
    const next = SIDE_ORDER[(SIDE_ORDER.indexOf(trendSide()) + (dx < 0 ? 1 : SIDE_ORDER.length - 1)) % SIDE_ORDER.length];
    document.querySelector(`.trends.table .table-dots [data-v="${next}"]`)?.click();
  });
})();
