'use strict';
// 먹이기(오늘 마감·지난 날 먹이기). 2026-09-26 대표님 확정: 밤 장면 + 당·카페인 화면 분리 + 끌어서 주기.
//  1) 당 화면: 컵 아래에서 로슈가 달라는 몸짓, 컵에 "눌러요" 신호
//  2) 컵을 누르면 컵이 흔들리며 빈 컵이 되고, 남은 양 방울이 나온다
//  3) 방울을 로슈에게 끌어다 놓으면(또는 방울을 누르면) 먹는다
//  4) 카페인 화면(카인)에서 같은 과정 → 마무리 요약에서만 저장한다. 중간에 닫으면 남기지 않는다.
// 하루 한 번 보는 장면이라 연출을 허용한다. 모션 줄이기면 흔들기·넘기기·튀기를 빼고 결과만 바꾼다.
// 기준을 넘긴 날은 캐릭터가 살짝 아쉬워할 뿐, 죄책감 문구·감점은 없다(§4.7).

const reduceMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

// ---------- 흐름 ----------
const FEEDING_ACTIONS = {
  tapCup: () => {
    const c = ui.cover;
    if (c.stage !== 'ask') return;
    c.stage = 'dropped';
  },
  feedDroplet: () => {
    const c = ui.cover;
    if (c.stage !== 'dropped') return;
    c.stage = 'eaten';
    c.fedSides.push(c.step);
    const side = c.step;
    afterRender.push(() => {
      bounce(side);
      countDown('feedNumber', c.left[side]);
    });
  },
  nextStep: () => {
    const c = ui.cover;
    if (c.stage !== 'eaten') return;
    if (c.step === 'sugar') {
      c.step = 'caffeine';
      c.stage = 'ask';
    } else {
      commitFeeding();
      c.step = 'done';
      afterRender.push(() => SIDE_ORDER.forEach(bounce));
    }
  },
};

// ---------- 그리기 ----------
function renderFeeding() {
  const c = ui.cover;
  c.step ??= 'sugar';
  c.stage ??= 'ask';
  if (c.step === 'done') return renderFeedingSummary(c);
  if (c.stage === 'dropped') afterRender.push(installDrop);
  return renderFeedingStep(c);
}

function renderFeedingStep(c) {
  const side = c.step;
  const meta = SIDES[side];
  const left = c.left[side];
  const over = c.over[side];
  const stage = c.stage;
  const cupStart = cupStep(left, limitOf(side));
  const stepLabel = `${c.kind === 'close' ? '오늘 마감' : '어제 남은 음료'} · ${side === 'sugar' ? '1' : '2'}/2`;

  const caption = {
    ask: over > 0
      ? `오늘은 ${meta.label}을 ${num(over)} ${meta.unit} 넘겼어요.<br>그래도 ${meta.withIga} 기다려요. 컵을 눌러 주세요.`
      : `${meta.withIga} 기다려요.<br>컵을 눌러 주세요.`,
    dropped: `방울을 ${meta.name}에게 끌어다 주세요.`,
    eaten: side === 'sugar' ? '다음은 카인 차례예요.' : '둘 다 먹었어요.',
  }[stage];

  const bubbleText = {
    ask: '주세요!',
    dropped: '여기요!',
    eaten: over > 0 ? '조금 아쉬워요' : `냠, ${num(left)} ${meta.unit}`,
  }[stage];

  // 방울 크기는 남은 비율을 따르되 너무 작아지지 않게. 넘긴 날(0)도 먹이면 1점은 쌓이니 방울은 준다.
  const ratio = Math.min(1, left / limitOf(side));
  const dropSize = Math.round(58 + 30 * ratio);

  return `
    <div class="cover night" data-side="${side}">
      <div class="feed-cup-box ${stage === 'dropped' ? 'shake' : ''}">
        <img src="${cupAsset(meta.cupSet, stage === 'ask' ? cupStart : 0)}" alt="">
        ${stage === 'dropped' ? `<img class="cup-empty" src="${cupAsset(meta.cupSet, cupStart)}" alt="">` : ''}
      </div>
      <div class="night-scrim"></div>
      ${stage === 'ask' ? `<button class="cup-hit" data-a="tapCup" aria-label="${meta.label} 컵 누르기"><span class="cup-pulse"></span></button>` : ''}
      <button class="text-button light cover-close" data-a="closeCover">닫기</button>
      <div class="headline">
        <div class="date-label light">${dateLabel(now())}</div>
        <div class="kicker light">${stepLabel}</div>
        <div class="number-row light"><span class="hero-number" id="feedNumber">${num(stage === 'eaten' ? 0 : left)}</span><span class="hero-unit">${meta.unit}</span></div>
        <div class="feed-caption light">남은 ${meta.label} · ${caption}</div>
      </div>
      ${stage === 'dropped' ? `<div class="drop" id="drop" role="button" tabindex="0" style="--size:${dropSize}px"
          aria-label="${meta.label} ${num(left)} ${meta.unit}를 ${meta.name}에게 주기">
          <img class="drop-body" src="../assets/drops/${side}.png" alt="" draggable="false">
          <div class="drop-label">${num(left)} ${meta.unit}</div>
        </div>` : ''}
      <div class="feed-asker">
        <div class="feed-bubble dark">${bubbleText}</div>
        <img class="feed-char ${side} ${stage === 'ask' ? 'asking' : ''} ${stage === 'dropped' ? 'waiting' : ''} ${over > 0 && stage !== 'eaten' ? 'sulk' : ''}"
          id="char-${side}" src="${characterAsset(meta.char)}" alt="${meta.name}">
      </div>
      <div class="feed-foot">
        <div class="cta-slot">${stage === 'eaten'
          ? `<button class="cta" data-a="nextStep">${side === 'sugar' ? '다음 · 카인' : '마무리'}</button>` : ''}</div>
        ${footNote(c.kind === 'close' && stage !== 'eaten')}
      </div>
    </div>`;
}

function renderFeedingSummary(c) {
  const figure = side => {
    const meta = SIDES[side];
    const r = c.results?.find(x => x.side === side);
    const note = r && r.after > r.before ? `${stageName(r.after)}가 됐어요` : c.over[side] > 0 ? '조금 아쉬워요' : `${meta.withIga} 먹었어요`;
    return `<div class="summary-col">
      <div class="feed-bubble dark">${note}</div>
      <img class="feed-char" id="char-${side}" src="${characterAsset(meta.char)}" style="height:${side === 'sugar' ? 150 : 104}px" alt="${meta.name}">
      <div class="summary-num">${num(c.left[side])}<small>${meta.unit}</small></div>
      <div class="summary-label">${meta.label}</div>
    </div>`;
  };
  return `
    <div class="cover night">
      <div class="feed-cup-box"><img src="${cupAsset(SIDES.sugar.cupSet, 0)}" alt=""></div>
      <div class="night-scrim"></div>
      <button class="text-button light cover-close" data-a="closeCover">닫기</button>
      <div class="split-head">
        <div class="date-label light">${dateLabel(now())}</div>
        <div class="kicker light" style="margin-top:28px">잘 먹었어요</div>
        <h1 class="split-title light">오늘도<br>잘 마무리했어요</h1>
        <div class="feed-caption light">${c.kind === 'close' ? '호감도는 내일 아침에 반영돼요.' : '호감도에 바로 반영했어요.'}</div>
      </div>
      <div class="summary-row">${figure('sugar')}${figure('caffeine')}</div>
      <div class="feed-foot"><div class="cta-slot"><button class="cta" data-a="closeCover">완료</button></div>${footNote(false)}</div>
    </div>`;
}

/** 안내 문구 자리는 늘 잡아 둔다. 문구가 빠져도 버튼이 내려앉지 않게. */
function footNote(visible) {
  return `<p class="feed-foot-note light" style="visibility:${visible ? 'visible' : 'hidden'}">마감 뒤에 마신 음료도 오늘 몫으로 빠져요</p>`;
}

// ---------- 연출 ----------
function bounce(side) {
  const el = document.getElementById(`char-${side}`);
  if (!el || reduceMotion()) return;
  el.classList.remove('bounce');
  void el.offsetWidth;
  el.classList.add('bounce');
}

async function countDown(elId, from) {
  const el = document.getElementById(elId);
  if (!el || reduceMotion() || from <= 0) return;
  el.textContent = num(from);
  const frames = 14;
  for (let i = frames - 1; i >= 0; i -= 1) {
    await wait(35);
    el.textContent = num((from * i) / frames);
  }
}

// ---------- 끌어서 주기 ----------
// 방울을 캐릭터 위에 놓으면 먹는다. 거의 움직이지 않고 떼면 누른 것으로 보고 역시 먹인다(끌기 어려운 사람용).
// 엉뚱한 곳에 놓으면 제자리로 돌아간다.
function installDrop() {
  const drop = document.getElementById('drop');
  const target = document.getElementById(`char-${ui.cover.step}`);
  if (!drop || !target) return;
  let start = null;
  const feed = () => { ACTIONS.feedDroplet(); render(); };
  drop.addEventListener('pointerdown', e => {
    drop.setPointerCapture(e.pointerId);
    start = { x: e.clientX, y: e.clientY };
    drop.classList.add('grabbed');
  });
  drop.addEventListener('pointermove', e => {
    if (!start) return;
    drop.style.translate = `${e.clientX - start.x}px ${e.clientY - start.y}px`;
    target.classList.toggle('ready', isOver(e, target.getBoundingClientRect()));
  });
  drop.addEventListener('pointerup', e => {
    if (!start) return;
    const moved = Math.hypot(e.clientX - start.x, e.clientY - start.y);
    start = null;
    drop.classList.remove('grabbed');
    if (moved < 8 || isOver(e, target.getBoundingClientRect())) {
      drop.classList.add('eaten');
      setTimeout(feed, reduceMotion() ? 0 : 180);
      return;
    }
    drop.classList.add('return');
    drop.style.translate = '';
    target.classList.remove('ready');
    setTimeout(() => drop.classList.remove('return'), 380);
  });
  drop.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') feed(); });
}

function isOver(e, rect) {
  const pad = 36;
  return e.clientX > rect.left - pad && e.clientX < rect.right + pad && e.clientY > rect.top - pad && e.clientY < rect.bottom + pad;
}
