'use strict';
// Phase 2-2: 먹이기(오늘 마감·지난 날 먹이기) 안 A·B·C.
// 하루 한 번 보는 마무리 장면이라 연출을 허용한다(빈도가 낮은 화면). 모션 줄이기면 연출 없이 바로 결과로 간다.
// 기준을 넘긴 날은 캐릭터가 살짝 아쉬워할 뿐, 죄책감 문구·감점은 없다(§4.7).

const reduceMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

// ---------- 공통 ----------
function feedingKicker(c) {
  if (c.phase === 'fed') return '잘 먹었어요';
  return c.kind === 'close' ? '오늘 마감' : '어제 남은 음료';
}

/** 먹은 뒤 말풍선. 지난 날은 바로 적립돼 단계가 오를 수 있다. 오늘 마감은 다음 날 아침에 반영된다. */
function reactionText(c, side) {
  const r = c.results?.find(x => x.side === side);
  if (r && r.after > r.before) return `${stageName(r.after)}가 됐어요`;
  if (c.over[side] > 0) return '조금 아쉬워요';
  return `냠, ${num(c.left[side])} ${SIDES[side].unit}`;
}

function afterNote(c) {
  return c.kind === 'close' ? '호감도는 내일 아침에 반영돼요.' : '호감도에 바로 반영했어요.';
}

/** 안내 문구 자리는 늘 잡아 둔다. 먹인 뒤 문구가 빠져도 버튼이 내려앉지 않게. */
function footNote(visible, tone) {
  return `<p class="feed-foot-note ${tone}" style="visibility:${visible ? 'visible' : 'hidden'}">마감 뒤에 마신 음료도 오늘 몫으로 빠져요</p>`;
}

function characterImg(side, height, extraClass = '') {
  const c = ui.cover;
  const sulk = c.phase !== 'fed' && c.over[side] > 0 && !c.fedSides.includes(side) ? 'sulk' : '';
  return `<img class="feed-char ${sulk} ${extraClass}" id="char-${side}" src="${characterAsset(SIDES[side].char)}" style="height:${height}px" alt="${SIDES[side].name}">`;
}

function bubble(side, dark = false) {
  const c = ui.cover;
  if (!c.fedSides.includes(side) && c.phase !== 'fed') return '<div class="feed-bubble placeholder"></div>';
  return `<div class="feed-bubble ${dark ? 'dark' : ''}">${esc(reactionText(c, side))}</div>`;
}

/** 캐릭터 한 번 튀기. */
function bounce(side) {
  const el = document.getElementById(`char-${side}`);
  if (!el || reduceMotion()) return;
  el.classList.remove('bounce');
  void el.offsetWidth;
  el.classList.add('bounce');
}

/** 컵 장면을 지금 단계에서 0까지 넘겨 보인다(단계 사진 넘기기). */
async function drainCup(imgId, set, fromStep) {
  const img = document.getElementById(imgId);
  if (!img || reduceMotion()) return;
  for (const step of CUP_STEPS.filter(s => s < fromStep).reverse()) {
    await wait(110);
    img.src = cupAsset(set, step);
  }
}

/** 숫자를 0까지 센다. */
async function countDown(elId, from) {
  const el = document.getElementById(elId);
  if (!el || reduceMotion() || from <= 0) return;
  const frames = 14;
  for (let i = frames - 1; i >= 0; i -= 1) {
    await wait(40);
    el.textContent = num((from * i) / frames);
  }
}

/** 한 캐릭터를 먹인다. 둘 다 먹었으면 기록하고 결과 단계로. */
async function feedSides(sides) {
  const c = ui.cover;
  const todo = sides.filter(s => !c.fedSides.includes(s));
  if (!todo.length || c.phase !== 'ready') return;
  c.busy = true;
  await Promise.all(todo.map(side => countDown(`num-${side}`, c.left[side])));
  c.fedSides.push(...todo);
  if (SIDE_ORDER.every(s => c.fedSides.includes(s))) {
    commitFeeding();
    c.phase = 'fed';
  }
  c.busy = false;
  render();
  todo.forEach(bounce);
}

const FEEDING_ACTIONS = {
  feedNight: () => {
    const c = ui.cover;
    if (c.phase !== 'ready') return;
    c.phase = 'eating';
    afterRender.push(async () => {
      const step = cupStep(c.left.sugar, limitOf('sugar'));
      SIDE_ORDER.forEach(bounce);
      await Promise.all([drainCup('feedCup', SIDES.sugar.cupSet, step), countDown('num-sugar', c.left.sugar), wait(reduceMotion() ? 0 : 500)]);
      c.fedSides = [...SIDE_ORDER];
      commitFeeding();
      c.phase = 'fed';
      render();
      SIDE_ORDER.forEach(bounce);
    });
  },
  feedSide: v => { if (!ui.cover.busy) afterRender.push(() => feedSides([v])); },
  feedAll: () => { if (!ui.cover.busy) afterRender.push(() => feedSides([...SIDE_ORDER])); },
};

// ---------- A: 밤 장면 ----------
function renderFeedingNight() {
  const c = ui.cover;
  const fed = c.phase === 'fed';
  const step = fed ? 0 : cupStep(c.left.sugar, limitOf('sugar'));
  const caption = fed
    ? `로슈가 당 ${num(c.left.sugar)} g, 카인이 카페인 ${num(c.left.caffeine)} mg를 먹었어요.<br>${afterNote(c)}`
    : c.over.sugar > 0
      ? `오늘은 당을 ${num(c.over.sugar)} g 넘겼어요.<br>남은 카페인 ${num(c.left.caffeine)} mg는 카인에게`
      : `남은 당은 로슈에게<br>카페인 ${num(c.left.caffeine)} mg는 카인에게`;
  return `
    <div class="cover night">
      <div class="cup-bg"><img id="feedCup" src="${cupAsset(SIDES.sugar.cupSet, step)}" alt=""></div>
      <div class="night-scrim"></div>
      <button class="text-button light" data-a="closeCover" style="position:absolute;right:20px;top:var(--safe-top);z-index:5">닫기</button>
      <div class="headline">
        <div class="date-label light">${dateLabel(now())}</div>
        <div class="kicker light">${feedingKicker(c)}</div>
        <div class="number-row light"><span class="hero-number" id="num-sugar">${num(fed ? 0 : c.left.sugar)}</span><span class="hero-unit">g</span></div>
        <div class="feed-caption light">${caption}</div>
      </div>
      <div class="feed-stage">
        <div class="feed-col">${bubble('sugar', true)}${characterImg('sugar', 170)}</div>
        <div class="feed-col small">${bubble('caffeine', true)}${characterImg('caffeine', 110)}</div>
      </div>
      <div class="feed-foot">
        <button class="cta" data-a="${fed ? 'closeCover' : 'feedNight'}" ${c.phase === 'eating' ? 'disabled' : ''}>${fed ? '완료' : '먹이기'}</button>
        ${footNote(!fed && c.kind === 'close', 'light')}
      </div>
    </div>`;
}

// ---------- B: 둘에게 나눠 주기 ----------
function renderFeedingSplit() {
  const c = ui.cover;
  const fed = c.phase === 'fed';
  const card = side => {
    const meta = SIDES[side];
    const done = c.fedSides.includes(side);
    const over = c.over[side] > 0 && !done;
    return `<button class="feed-card ${done ? 'done' : ''}" data-a="feedSide" data-v="${side}" ${done ? 'disabled' : ''} aria-label="${meta.name}에게 ${meta.label} 먹이기">
      <div class="kicker">${meta.name}에게</div>
      <div class="feed-card-char">${bubble(side)}${characterImg(side, side === 'sugar' ? 118 : 96)}</div>
      <div class="feed-card-num"><span id="num-${side}">${num(done ? 0 : c.left[side])}</span><small>${meta.unit}</small></div>
      <div class="log-sub">${done ? '먹었어요' : over ? `${meta.label} ${num(c.over[side])} ${meta.unit} 넘김` : `남은 ${meta.label}`}</div>
    </button>`;
  };
  return `
    <div class="cover soft">
      <div class="cup-bg blurred"><img src="${cupAsset(SIDES.sugar.cupSet, cupStep(c.left.sugar, limitOf('sugar')))}" alt=""></div>
      <div class="soft-scrim"></div>
      <button class="text-button" data-a="closeCover" style="position:absolute;right:20px;top:var(--safe-top);z-index:5">닫기</button>
      <div class="split-head">
        <div class="date-label">${dateLabel(now())}</div>
        <div class="kicker" style="margin-top:28px">${feedingKicker(c)}</div>
        <h1 class="split-title">${fed ? '둘 다<br>배불러요' : '남은 만큼<br>나눠 줘요'}</h1>
        <div class="feed-caption">${fed ? afterNote(c) : '카드를 누르면 그 친구만 먹어요.'}</div>
      </div>
      <div class="split-cards">${card('sugar')}${card('caffeine')}</div>
      <div class="feed-foot">
        <button class="cta" data-a="${fed ? 'closeCover' : 'feedAll'}">${fed ? '완료' : '모두 먹이기'}</button>
        ${footNote(!fed && c.kind === 'close', '')}
      </div>
    </div>`;
}

// ---------- C: 끌어서 주기 ----------
function renderFeedingDrag() {
  const c = ui.cover;
  const fed = c.phase === 'fed';
  const next = SIDE_ORDER.find(s => !c.fedSides.includes(s));
  const meta = next ? SIDES[next] : null;
  if (next && !fed) afterRender.push(() => installDragToken(next));
  const caption = fed ? afterNote(c)
    : `${meta.label} 방울을 ${meta.name}에게 끌어다 주세요.`;
  return `
    <div class="cover">
      <div class="cup-bg"><img src="${cupAsset(SIDES.sugar.cupSet, c.fedSides.includes('sugar') || fed ? 0 : cupStep(c.left.sugar, limitOf('sugar')))}" alt=""></div>
      <div class="top-scrim"></div>
      <button class="text-button" data-a="closeCover" style="position:absolute;right:20px;top:var(--safe-top);z-index:5">닫기</button>
      <div class="headline">
        <div class="date-label">${dateLabel(now())}</div>
        <div class="kicker">${feedingKicker(c)}</div>
        <div class="number-row"><span class="hero-number" id="num-${next ?? 'sugar'}">${num(next ? c.left[next] : 0)}</span><span class="hero-unit">${meta?.unit ?? 'g'}</span></div>
        <div class="feed-caption">${caption}</div>
      </div>
      ${next && !fed ? `<div class="drag-token" id="dragToken" role="button" aria-label="${meta.label} ${num(c.left[next])} ${meta.unit}를 ${meta.name}에게 주기">
        <b>${num(c.left[next])}</b><small>${meta.unit}</small></div>` : ''}
      <div class="feed-stage">
        <div class="feed-col drop ${next === 'sugar' ? 'target' : ''}">${bubble('sugar')}${characterImg('sugar', 170)}</div>
        <div class="feed-col small drop ${next === 'caffeine' ? 'target' : ''}">${bubble('caffeine')}${characterImg('caffeine', 110)}</div>
      </div>
      <div class="feed-foot">
        ${fed ? '<button class="cta" data-a="closeCover">완료</button>'
          : '<div class="cta-slot"><button class="glass-pill feed-fallback" data-a="feedAll">끌지 않고 한 번에 먹이기</button></div>'}
        ${footNote(false, '')}
      </div>
    </div>`;
}

/** 방울을 손가락으로 끌어 캐릭터에 놓으면 먹는다. 놓친 곳에 놓으면 제자리로 돌아간다. */
function installDragToken(side) {
  const token = document.getElementById('dragToken');
  const target = document.getElementById(`char-${side}`);
  if (!token || !target) return;
  let start = null;
  token.addEventListener('pointerdown', e => {
    token.setPointerCapture(e.pointerId);
    start = { x: e.clientX, y: e.clientY };
    token.classList.add('grabbed');
  });
  token.addEventListener('pointermove', e => {
    if (!start) return;
    token.style.transform = `translate(${e.clientX - start.x}px, ${e.clientY - start.y}px) scale(1.06)`;
    const hit = isOver(e, target.getBoundingClientRect());
    target.classList.toggle('ready', hit);
  });
  token.addEventListener('pointerup', e => {
    if (!start) return;
    start = null;
    token.classList.remove('grabbed');
    if (isOver(e, target.getBoundingClientRect())) {
      token.classList.add('eaten');
      feedSides([side]);
      return;
    }
    token.classList.add('return');
    token.style.transform = '';
    setTimeout(() => token.classList.remove('return'), 350);
  });
}

function isOver(e, rect) {
  const pad = 30;
  return e.clientX > rect.left - pad && e.clientX < rect.right + pad && e.clientY > rect.top - pad && e.clientY < rect.bottom + pad;
}
