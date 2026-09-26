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
      playFeedFx('turn', {}, () => {
        c.step = 'caffeine';
        c.stage = 'ask';
      });
    } else {
      playFeedFx('night', {}, () => {
        commitFeeding();
        c.step = 'done';
        afterRender.push(() => SIDE_ORDER.forEach(bounce));
      });
    }
  },
};

// ---------- 전환 모션그래픽(2026-09-26 대표님: 하루 마무리라 전환에 모션그래픽) ----------
// 마감 진입(dusk) · 로슈→카인(turn) · 마무리(night). 전환 층은 다시 그리기(#layers) 밖에 두고,
// 화면이 다 덮인 순간 swap()으로 상태를 바꿔 밑 화면을 새로 그린다. 모션 줄이기면 바로 바꾼다.
let feedFx = null;
const FX_STARS = [[46, 150], [330, 118], [262, 226], [104, 292], [356, 318], [30, 404], [190, 96], [300, 430]];

function playFeedFx(kind, opts, swap) {
  const swapNow = () => { swap(); render(); };
  if (reduceMotion() || feedFx || !window.gsap) { swapNow(); return; }
  const el = document.createElement('div');
  el.className = `ffx ffx-${kind}`;
  el.innerHTML = FEED_FX[kind].html(opts);
  document.getElementById('screen').appendChild(el);
  document.getElementById('phone').classList.add('dark-status');
  const tl = gsap.timeline({
    onComplete: () => {
      el.remove();
      feedFx = null;
      document.getElementById('phone').classList.toggle('dark-status', Boolean(ui.cover));
    },
  });
  feedFx = { el, tl };
  FEED_FX[kind].build(tl, sel => el.querySelector(sel), sel => el.querySelectorAll(sel), swapNow);
}

const fxMask = text => `<span class="it-mask"><span>${text}</span></span>`;

const FEED_FX = {
  // 하루가 저문다: 밤하늘이 지평선처럼 차오르고 달·별이 뜬 뒤, 하늘이 걷히며 밤 장면이 드러난다.
  dusk: {
    html: o => `<div class="ffx-sky"><i class="ffx-moon"></i>${FX_STARS.map(([x, y]) => `<i class="ffx-star" style="left:${x}px;top:${y}px"></i>`).join('')}
      <div class="ffx-type"><div class="ffx-small">${dateLabel(now())}</div>${fxMask(o.title)}</div></div>`,
    build: (tl, $, $$, swapNow) => {
      tl.fromTo($('.ffx-sky'), { yPercent: 100 }, { yPercent: 0, duration: 0.6, ease: 'power3.inOut' }, 0);
      tl.fromTo($('.ffx-moon'), { y: 300, scale: 0.6 }, { y: 0, scale: 1, duration: 0.85, ease: 'power3.out' }, 0.15);
      tl.fromTo($$('.ffx-star'), { scale: 0 }, { scale: 1, duration: 0.3, ease: 'back.out(3)', stagger: 0.05 }, 0.45);
      tl.fromTo($('.ffx-small'), { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: 0.35, ease: 'power2.out' }, 0.4);
      tl.fromTo($('.ffx-type .it-mask > span'), { yPercent: 108 }, { yPercent: 0, duration: 0.55, ease: 'power4.out' }, 0.45);
      tl.call(swapNow, null, 1.1);
      tl.to($('.ffx-type'), { y: -40, opacity: 0, duration: 0.3, ease: 'power3.in' }, 1.15);
      tl.to($('.ffx-sky'), { yPercent: -100, duration: 0.55, ease: 'power3.in' }, 1.25);
    },
  },
  // 로슈 → 카인: "다음 · 카인" 버튼 자리에서 호박색이 번지고, 카인이 튀어나온 뒤 카인 자리로 오므라든다.
  turn: {
    html: () => `<div class="ffx-disc"></div><img class="ffx-kain" src="${characterAsset('kain')}" alt="">
      <div class="ffx-type center"><div class="ffx-small">다음은</div>${fxMask('카인 차례!')}</div>`,
    build: (tl, $, $$, swapNow) => {
      const at = (r, y) => `circle(${r}px at 201px ${y}px)`;
      tl.fromTo($('.ffx-disc'), { clipPath: at(0, 802) }, { clipPath: at(1000, 802), duration: 0.6, ease: 'expo.inOut' }, 0);
      tl.fromTo($('.ffx-small'), { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: 0.3, ease: 'power2.out' }, 0.32);
      tl.fromTo($('.ffx-type .it-mask > span'), { yPercent: 108 }, { yPercent: 0, duration: 0.5, ease: 'power4.out' }, 0.36);
      tl.fromTo($('.ffx-kain'), { y: 140, scale: 0.4, rotation: -25, opacity: 0 }, { y: 0, scale: 1, rotation: 0, opacity: 1, duration: 0.5, ease: 'back.out(1.7)' }, 0.42);
      tl.to($('.ffx-kain'), { rotation: 360, duration: 0.5, ease: 'power3.inOut' }, 0.8);
      tl.call(swapNow, null, 0.95);
      tl.to($('.ffx-type'), { y: -30, opacity: 0, duration: 0.25, ease: 'power3.in' }, 1.25);
      tl.to($('.ffx-kain'), { y: 250, scale: 0.55, duration: 0.45, ease: 'power3.in' }, 1.25);
      tl.to($('.ffx-kain'), { opacity: 0, duration: 0.12 }, 1.62);
      tl.to($('.ffx-disc'), { clipPath: at(0, 662), duration: 0.55, ease: 'expo.inOut' }, 1.3);
    },
  },
  // 마무리: 밤하늘이 내려오고, 당·카페인 방울이 가운데서 합쳐져 별로 흩어진다. 그 사이 요약 화면이 올라온다.
  night: {
    html: () => `<div class="ffx-sky top"></div><i class="ffx-flash"></i>
      <i class="ffx-drop" data-s="sugar" style="background-image:url('../assets/drops/sugar.png')"></i>
      <i class="ffx-drop" data-s="caffeine" style="background-image:url('../assets/drops/caffeine.png')"></i>
      ${Array.from({ length: 14 }, () => '<i class="ffx-star burst"></i>').join('')}`,
    build: (tl, $, $$, swapNow) => {
      tl.fromTo($('.ffx-sky'), { yPercent: -100 }, { yPercent: 0, duration: 0.6, ease: 'power3.inOut' }, 0);
      tl.fromTo($('[data-s=sugar]'), { x: -150, y: 300, scale: 0.4, opacity: 0 }, { x: -46, y: 0, scale: 1, opacity: 1, duration: 0.55, ease: 'power3.out' }, 0.35);
      tl.fromTo($('[data-s=caffeine]'), { x: 150, y: 300, scale: 0.4, opacity: 0 }, { x: 46, y: 0, scale: 1, opacity: 1, duration: 0.55, ease: 'power3.out' }, 0.42);
      tl.to($$('.ffx-drop'), { x: 0, duration: 0.28, ease: 'power3.in' }, 0.98);
      tl.to($$('.ffx-drop'), { scale: 0, duration: 0.12, ease: 'power2.in' }, 1.22);
      tl.fromTo($('.ffx-flash'), { scale: 0, opacity: 1 }, { scale: 7, opacity: 0, duration: 0.7, ease: 'power2.out' }, 1.22);
      $$('.ffx-star.burst').forEach((star, i) => {
        const a = (i / 14) * Math.PI * 2 + 0.3;
        const d = 120 + (i % 4) * 45;
        tl.fromTo(star, { x: 0, y: 0, scale: 0 }, { x: Math.cos(a) * d, y: Math.sin(a) * d * 1.3, scale: 1, duration: 0.7, ease: 'power3.out' }, 1.24);
      });
      tl.call(swapNow, null, 1.35);
      tl.call(() => animateSummaryIn(), null, 1.4);
      tl.to($('.ffx-sky'), { opacity: 0, duration: 0.5, ease: 'power2.inOut' }, 1.45);
      tl.to($$('.ffx-star.burst'), { opacity: 0, duration: 0.6, ease: 'power2.in' }, 1.6);
    },
  },
};

/** 요약 화면이 올라온다: 글자는 줄마다, 두 캐릭터 기둥은 차례로, 숫자는 0에서 센다. */
function animateSummaryIn() {
  const layers = document.getElementById('layers');
  gsap.from(layers.querySelectorAll('.split-head > *'), { y: 24, opacity: 0, duration: 0.55, ease: 'power3.out', stagger: 0.07 });
  gsap.from(layers.querySelectorAll('.summary-col'), { y: 60, opacity: 0, duration: 0.6, ease: 'back.out(1.4)', stagger: 0.12, delay: 0.2 });
  layers.querySelectorAll('.summary-num').forEach(el => {
    const text = el.firstChild;
    const to = Number(text.textContent.replace(/,/g, ''));
    if (!Number.isFinite(to)) return;
    const v = { n: 0 };
    gsap.to(v, { n: to, duration: 0.9, ease: 'power2.out', delay: 0.3, onUpdate: () => { text.textContent = num(Math.round(v.n)); }, onComplete: () => { text.textContent = num(to); } });
  });
}

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
