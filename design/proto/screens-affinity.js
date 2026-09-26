'use strict';
// Phase 2-3: 호감도(Pro). 단계 숫자·점수는 어느 안에도 보이지 않는다(2026-09-26 대표님 지시, SPEC §4.8).
// 단계는 사이 이름(STAGE_NAMES)으로 부르고, 진행은 막대·고리 같은 모양으로만 보여 준다.
// 표정 원화가 아직 없어(§9.4) 열린 칸에도 기본 그림을 쓰고, 잠긴 칸은 실루엣으로 둔다.

/** 지금 단계 안에서 다음 단계까지 온 정도, 0~1. 마지막 단계면 1. */
function progressToNext(points) {
  const level = levelOf(points);
  if (level >= MAX_LEVEL) return 1;
  return (points - threshold(level)) / (threshold(level + 1) - threshold(level));
}

function affinityOf(side) {
  const points = S.points[SIDES[side].char];
  const level = levelOf(points);
  return { points, level, progress: progressToNext(points), stage: stageName(level), next: level < MAX_LEVEL ? stageName(level + 1) : null };
}

const affinitySide = () => ui.affinitySide ?? 'sugar';

function affinitySheet(body) {
  return `
    <div class="dim light" data-a="closeSheet"></div>
    <div class="sheet glass">
      <div class="grabber"></div>
      <div class="sheet-head"><span class="kicker">호감도</span><button class="text-button" data-a="closeSheet">닫기</button></div>
      <div class="scroll">${body}<div class="bottom-space"></div></div>
    </div>`;
}

function sideSwitch() {
  const side = affinitySide();
  return `<div class="segmented inset-x">${SIDE_ORDER.map(s =>
    `<button class="${s === side ? 'on' : ''}" data-a="affinitySide" data-v="${s}">${SIDES[s].name}</button>`).join('')}</div>`;
}

/** 표정 9칸(단계 2~10). 열린 칸은 그림과 그 사이 이름, 바로 다음 칸은 "곧 열려요", 나머지는 실루엣. */
function expressionGrid(side, columns = 3) {
  const { level } = affinityOf(side);
  const cards = [];
  for (let step = 2; step <= MAX_LEVEL; step += 1) {
    const open = step <= level;
    const caption = open ? stageName(step) : step === level + 1 ? '곧 열려요' : '';
    cards.push(`<div class="face-card ${open ? 'open' : ''}" aria-label="${open ? `${stageName(step)} 표정` : '잠긴 표정'}">
      <img src="${characterAsset(SIDES[side].char)}" alt="" draggable="false">
      ${open ? '' : `<span class="face-lock">${ICON.lock}</span>`}
      <span class="face-caption">${caption}</span>
    </div>`);
  }
  return `<div class="face-grid" style="grid-template-columns:repeat(${columns},1fr)">${cards.join('')}</div>`;
}

// ---------- A: 초상 ----------
function renderAffinityPortrait() {
  const side = affinitySide();
  const a = affinityOf(side);
  return affinitySheet(`
    ${sideSwitch()}
    <div class="portrait">
      <img class="portrait-char ${side}" src="${characterAsset(SIDES[side].char)}" alt="${SIDES[side].name}">
      <div class="portrait-with">${SIDES[side].withGwa}</div>
      <h2 class="portrait-stage">${a.stage}</h2>
      <div class="bond-bar"><i style="width:${Math.round(a.progress * 100)}%"></i></div>
      <div class="bond-note">${a.next ? `다음은 ${a.next}` : '가장 가까운 사이가 됐어요'}</div>
    </div>
    <div class="kicker section-gap">표정</div>
    <div class="pad-x0">${expressionGrid(side)}</div>
    <div class="caption-note">표정 그림은 준비 중이에요. 친해질수록 하나씩 열려요.</div>`);
}

// ---------- B: 관계 길 ----------
function renderAffinityPath() {
  const side = affinitySide();
  const a = affinityOf(side);
  const nodes = STAGE_NAMES.map((name, i) => {
    const level = i + 1;
    const state = level < a.level ? 'past' : level === a.level ? 'now' : 'future';
    const showFace = level >= 2 && level <= a.level;
    return `<li class="path-node ${state}">
      <span class="path-dot"></span>
      <div class="path-text">
        <div class="path-name">${name}</div>
        ${state === 'now' ? `<div class="bond-bar small"><i style="width:${Math.round(a.progress * 100)}%"></i></div>
          <div class="bond-note">${a.next ? `다음은 ${a.next}` : '가장 가까운 사이가 됐어요'}</div>` : ''}
        ${state === 'past' ? '<div class="path-sub">지나온 사이</div>' : ''}
      </div>
      ${state === 'now' ? `<img class="path-char" src="${characterAsset(SIDES[side].char)}" alt="${SIDES[side].name}">`
        : showFace ? `<img class="path-face" src="${characterAsset(SIDES[side].char)}" alt="" title="이때 열린 표정">`
        : level >= 2 ? `<span class="path-face locked">${ICON.lock}</span>` : ''}
    </li>`;
  }).reverse().join('');
  return affinitySheet(`
    ${sideSwitch()}
    <h2 class="sheet-headline" style="margin-bottom:6px">${SIDES[side].withGwa}<br>${a.stage}</h2>
    <div class="caption-note">덜 마신 날 먹이면 더 빨리 가까워져요. 사이가 깊어질 때마다 새 표정이 열려요.</div>
    <ol class="path">${nodes}</ol>`);
}

// ---------- C: 둘 나란히 ----------
function renderAffinityPair() {
  const side = affinitySide();
  const ring = s => {
    const a = affinityOf(s);
    const r = 58, c = 2 * Math.PI * r;
    return `<button class="pair-card ${s === side ? 'on' : ''}" data-a="affinitySide" data-v="${s}" aria-label="${SIDES[s].withGwa} ${a.stage}">
      <div class="ring">
        <svg viewBox="0 0 140 140" aria-hidden="true"><circle cx="70" cy="70" r="${r}" class="ring-track"/>
          <circle cx="70" cy="70" r="${r}" class="ring-fill" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - a.progress)}"/></svg>
        <img src="${characterAsset(SIDES[s].char)}" alt="">
      </div>
      <div class="pair-with">${SIDES[s].withGwa}</div>
      <div class="pair-stage">${a.stage}</div>
      <div class="bond-note">${a.next ? `다음은 ${a.next}` : '가장 가까운 사이'}</div>
    </button>`;
  };
  return affinitySheet(`
    <h2 class="sheet-headline">둘과의 사이</h2>
    <div class="pair">${ring('sugar')}${ring('caffeine')}</div>
    <div class="kicker section-gap">${SIDES[side].name}의 표정</div>
    <div class="pad-x0">${expressionGrid(side)}</div>
    <div class="caption-note">표정 그림은 준비 중이에요. 카드를 누르면 그 친구의 표정을 봐요.</div>`);
}
