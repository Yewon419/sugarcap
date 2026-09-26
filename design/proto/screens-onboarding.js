'use strict';
// 온보딩(2026-09-26): 대표님이 고른 15초 모션그래픽 릴(videos/sugarcap-ad-15s v2)을 옮겨 와 온보딩으로 다듬었다.
//  - 영상용 장식(재단선·타임코드·장 번호)은 빼고, 진행 막대·건너뛰기·장마다 한 줄 설명을 얹었다.
//  - 이름 글꼴은 명조를 빼고 앱과 같은 Pretendard(대표님: "마지막 폰트 구린 거 빼면").
//  - 화면 누르기 = 다음 장, 건너뛰기 = 하루 기준. 끝나면 하루 기준 설정으로 이어진다.
// 릴은 1080×1920 무대를 폰 화면(402×874)에 맞춰 줄인 것이다. 프로토타입은 누를 때마다 화면을 다시 그리므로,
// 재생 중인 무대는 다시 그리기 대상(#layers) 밖의 별도 층(#reel)에 둔다.

const REEL_SCALE = 874 / 1920;
const REEL_OFFSET_X = (402 - 1080 * REEL_SCALE) / 2;
const REEL_CHAPTERS = [
  { at: 0, kick: '01', line: '마실 때마다 컵이 줄어요' },
  { at: 2.8, kick: '02', line: '당도 카페인도 따로 챙겨요' },
  { at: 5.55, kick: '03', line: '기준 안에서 마신 날이 하나씩 쌓여요' },
  { at: 8.45, kick: '04', line: '남은 만큼이 방울이 돼요' },
  { at: 11.4, kick: '05', line: '남긴 방울은 밤에 로슈와 카인에게' },
];
const REEL_END = 15;
const DROP = side => `../assets/drops/${side}.png`;

let reel = null; // { el, tl, chapter }

const obReduce = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

function obStart() {
  unmountReel();
  ui.onboarding = { scene: 'reel', sugar: S.settings.sugarG, caffeine: S.settings.caffeineMg };
  if (obReduce()) ui.onboarding.scene = 'setup';
}

/** render()가 부른다. 릴은 별도 층이라 여기서는 층을 띄우기만 하고, 하루 기준은 평소처럼 그린다. */
function renderOnboarding() {
  if (ui.onboarding.scene === 'reel') {
    afterRender.push(mountReel);
    return '';
  }
  afterRender.push(bindObSetup);
  return `<div class="onboard setup">${renderObSetup()}</div>`;
}

function reelChapterIndex(t) {
  let i = 0;
  REEL_CHAPTERS.forEach((c, k) => { if (t >= c.at) i = k; });
  return i;
}

function goSetup() {
  unmountReel();
  ui.onboarding.scene = 'setup';
  render();
}

function unmountReel() {
  if (!reel) return;
  reel.tl.kill();
  reel.el.remove();
  reel = null;
}

// ---------- 릴 무대 ----------
function mountReel() {
  if (reel) return;
  const host = document.getElementById('screen');
  const el = document.createElement('div');
  el.className = 'reel';
  el.id = 'reel';
  el.dataset.a = 'obNext';
  el.innerHTML = `
    <div class="reel-stage" style="transform: translateX(${REEL_OFFSET_X}px) scale(${REEL_SCALE})">
      <div class="rl-world" id="rlWorld">
        <svg class="rl-layer" id="rlGrid" viewBox="0 0 1080 1920" aria-hidden="true"></svg>
        <svg class="rl-layer" id="rlLiquidSvg" viewBox="0 0 1080 1920" aria-hidden="true">
          <defs><linearGradient id="rlPink" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6c1cc"/><stop offset="1" stop-color="#df7690"/></linearGradient></defs>
          <path id="rlLiqA" fill="url(#rlPink)" d=""/>
        </svg>
        <div class="rl-spark" id="rlSpark1" style="top:1100px"></div>
        <div class="rl-disc" id="rlWipePink"></div>
        <div class="rl-disc" id="rlWipeAmber"></div>
        <svg class="rl-layer" id="rlRingSvg" viewBox="0 0 1080 1920" aria-hidden="true">
          <g id="rlRingG"><circle id="rlRing" cx="540" cy="960" r="380" fill="none" stroke="#3b1d0e" stroke-width="56" stroke-linecap="round"/></g>
          <g id="rlTicks"></g>
        </svg>
        <svg class="rl-layer" id="rlDotsSvg" viewBox="0 0 1080 1920" aria-hidden="true"><g id="rlDots"></g></svg>
        <svg class="rl-layer" id="rlCupSvg" viewBox="0 0 1080 1920" aria-hidden="true">
          <defs><clipPath id="rlCupClip"><path d="M 272 626 L 336 1466 Q 340 1490 364 1490 L 716 1490 Q 740 1490 744 1466 L 808 626 Z"/></clipPath></defs>
          <g clip-path="url(#rlCupClip)"><path id="rlLiqD" fill="url(#rlPink)" d=""/></g>
          <path id="rlCupLine" d="M 256 614 L 322 1472 Q 328 1504 362 1504 L 718 1504 Q 752 1504 758 1472 L 824 614"
            fill="none" stroke="#141a24" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" opacity="0"/>
        </svg>
        <div class="rl-spark" id="rlSpark2" style="top:1000px;background:#e07a91"></div>
        <div class="rl-spark" id="rlSpark3" style="top:1300px;background:#e07a91"></div>
        <div class="rl-numeral" id="rlN50">50</div>
        <div class="rl-numeral" id="rlN20">20</div>
        <div class="rl-numeral" id="rlN4">4</div>
        <div class="rl-numeral light" id="rlN400">400</div>
        <div class="rl-numeral light" id="rlN200">200</div>
        <div class="rl-ripple" id="rlRip1"></div>
        <div class="rl-ripple" id="rlRip2"></div>
        <div class="rl-drop" id="rlDropS" style="background-image:url('${DROP('sugar')}')"></div>
        <div class="rl-drop" id="rlDropC" style="background-image:url('${DROP('caffeine')}')"></div>
        <div class="rl-word">
          <span class="rl-mask"><span id="rlW1">슈</span></span><span class="rl-mask"><span id="rlW2">가</span></span><span class="rl-mask"><span id="rlW3">캡</span></span>
        </div>
        <div class="rl-word-en" id="rlWordEn">SUGARCAP</div>
      </div>
    </div>
    <div class="reel-top-fade"></div>
    <div class="reel-progress">${REEL_CHAPTERS.map((_, i) => `<i><b id="rlBar${i}"></b></i>`).join('')}</div>
    <button class="reel-skip" data-a="obSkip">건너뛰기</button>
    <div class="reel-cap" id="rlCap"><div class="reel-kick" id="rlKick"></div><div class="reel-line" id="rlLine"></div></div>`;
  host.appendChild(el);
  reel = { el, tl: buildReelTimeline(el), chapter: -1 };
  reel.tl.play(0);
}

/** 영상 v2와 같은 안무. 절차적 도형은 시간 t의 순수 함수(drawReel), 나머지는 한 타임라인. */
function buildReelTimeline(root) {
  const $ = id => root.querySelector(`#${id}`);
  const NS = 'http://www.w3.org/2000/svg';
  const E = {
    o3: gsap.parseEase('power3.out'), o4: gsap.parseEase('power4.out'), i2: gsap.parseEase('power2.in'),
    io3: gsap.parseEase('power3.inOut'), lin: t => t,
  };
  const clamp01 = v => Math.max(0, Math.min(1, v));
  const seg = (t, a, b, ease = E.lin) => ease(clamp01((t - a) / (b - a)));
  const lerp = (a, b, k) => a + (b - a) * k;
  const slosh = (t, beats, peak) => beats.reduce((a, b) => a + (t >= b ? peak * Math.exp(-(t - b) * 4.2) : 0), 0);
  const wavePath = (baseY, amp, phase, x0, x1, bottom) => {
    let d = `M ${x0} ${bottom} L ${x0} ${baseY}`;
    for (let x = x0; x <= x1; x += 18) {
      const y = baseY + amp * Math.sin(x * 0.011 + phase) + amp * 0.45 * Math.sin(x * 0.029 - phase * 1.35);
      d += ` L ${x} ${y.toFixed(1)}`;
    }
    return `${d} L ${x1} ${bottom} Z`;
  };

  const grid = $('rlGrid');
  [180, 360, 540, 720, 900].forEach((x, i) => {
    const l = document.createElementNS(NS, 'line');
    l.setAttribute('x1', x); l.setAttribute('x2', x); l.setAttribute('y1', 0); l.setAttribute('y2', 1920);
    l.setAttribute('stroke', '#141a24'); l.setAttribute('stroke-width', i === 2 ? 2 : 1.2); l.setAttribute('opacity', '0.1');
    grid.appendChild(l);
  });
  const ticks = $('rlTicks');
  for (let i = 0; i < 60; i += 1) {
    const l = document.createElementNS(NS, 'line');
    const long = i % 5 === 0;
    l.setAttribute('x1', 540); l.setAttribute('x2', 540); l.setAttribute('y1', 960 - 452); l.setAttribute('y2', 960 - (long ? 500 : 478));
    l.setAttribute('stroke', '#f3f5f8'); l.setAttribute('stroke-width', long ? 6 : 3); l.setAttribute('stroke-linecap', 'round');
    l.setAttribute('transform', `rotate(${i * 6} 540 960)`);
    ticks.appendChild(l);
  }
  const RING_C = 2 * Math.PI * 380;
  const ring = $('rlRing');
  ring.setAttribute('stroke-dasharray', `${RING_C} ${RING_C}`);

  const COLS = 7, ROWS = 11, GAP = 140, GAP_X = 118, X0 = 186, Y0 = 260, KEEP = 5;
  const PALETTE = ['#e07a91', '#b8732f', '#5b84aa'];
  const dots = [];
  for (let r = 0; r < ROWS; r += 1) {
    for (let c = 0; c < COLS; c += 1) {
      const el = document.createElementNS(NS, 'circle');
      el.setAttribute('fill', PALETTE[(c + r) % 3]);
      $('rlDots').appendChild(el);
      const x = X0 + c * GAP_X, y = Y0 + r * GAP;
      dots.push({ el, c, r, x, y, d: Math.hypot(x - 540, y - 960) / Math.hypot(354, 700) });
    }
  }

  const liqA = $('rlLiqA'), liqD = $('rlLiqD'), ringG = $('rlRingG');
  const svgRing = $('rlRingSvg'), svgDots = $('rlDotsSvg'), dropS = $('rlDropS'), dropC = $('rlDropC');

  const draw = t => {
    if (t < 3.7) {
      liqA.style.display = '';
      let f = lerp(-0.04, 1.02, seg(t, 0.15, 1.0, E.o3));
      f = lerp(f, 0.4, seg(t, 1.5, 1.85, E.o4));
      f = lerp(f, 0.08, seg(t, 2.2, 2.55, E.o4));
      liqA.setAttribute('d', wavePath(1920 * (1 - f), 16 + slosh(t, [1.0, 1.5, 2.2], 62), t * 4.2, -20, 1100, 1960));
    } else {
      liqA.style.display = 'none';
    }
    const ringOn = t > 3.4 && t < 5.6;
    svgRing.style.display = ringOn ? '' : 'none';
    if (ringOn) {
      let v = seg(t, 3.55, 4.1, E.o3);
      v = lerp(v, 0.5, seg(t, 4.55, 4.9, E.o4));
      ring.setAttribute('stroke-dashoffset', (RING_C * (1 - v)).toFixed(1));
      ringG.setAttribute('transform', `rotate(${-90 + 50 * seg(t, 3.5, 5.5, E.io3)} 540 960)`);
      ticks.setAttribute('transform', `rotate(${-(t - 3.4) * 22} 540 960)`);
      svgRing.style.opacity = (seg(t, 3.4, 3.7) * (1 - seg(t, 5.2, 5.45))).toFixed(3);
    }
    const dotsOn = t > 5.5 && t < 10.1;
    svgDots.style.display = dotsOn ? '' : 'none';
    if (dotsOn) {
      const env = seg(t, 6.2, 6.6, E.io3) * (1 - seg(t, 7.25, 7.6, E.io3));
      for (const p of dots) {
        const appear = seg(t, 5.55 + p.d * 0.45, 6.0 + p.d * 0.45, E.o3);
        const wave = 1 + 0.55 * env * Math.sin(2 * Math.PI * (t - 6.2) * 1.15 - (p.c + p.r) * 0.6);
        let x = p.x, y = p.y, rad = 34 * appear * wave, op = 1;
        if (p.r !== KEEP) {
          const lag = 7.55 + p.c * 0.03 + Math.abs(p.r - KEEP) * 0.018;
          y = lerp(p.y, 2050 + p.r * 20, seg(t, lag, lag + 0.6, E.i2));
        } else {
          const gather = seg(t, 8.55 + p.c * 0.02, 8.95 + p.c * 0.02, E.io3);
          const drop = seg(t, 9.05 + p.c * 0.05, 9.5 + p.c * 0.05, E.i2);
          x = lerp(p.x, 395 + p.c * 48.3, gather);
          y = lerp(lerp(p.y, 520, gather), 1452, drop);
          rad = lerp(rad, 22, gather);
          op = 1 - seg(t, 9.55, 9.95);
          p.el.setAttribute('fill', seg(t, 7.85, 8.2) > 0.5 ? PALETTE[0] : PALETTE[(p.c + p.r) % 3]);
        }
        p.el.setAttribute('cx', x.toFixed(1));
        p.el.setAttribute('cy', y.toFixed(1));
        p.el.setAttribute('r', Math.max(0, rad).toFixed(1));
        p.el.setAttribute('opacity', op.toFixed(3));
      }
    }
    if (t > 9.3 && t < 11.9) {
      liqD.style.display = '';
      let f = seg(t, 9.45, 10.15, E.o3) * 0.86;
      f = lerp(f, 0.46, seg(t, 10.55, 10.9, E.o4));
      f = lerp(f, 0.12, seg(t, 11.05, 11.4, E.o4));
      liqD.setAttribute('d', wavePath(1490 - 864 * f, 8 + slosh(t, [10.15, 10.55, 11.05], 40), t * 4.6 + 1.3, 260, 830, 1500));
    } else {
      liqD.style.display = 'none';
    }
    const e = seg(t, 11.8, 12.9, E.io3);
    const a = Math.PI * 0.5 + 2.5 * Math.PI * e;
    const rr = lerp(230, 118, e);
    gsap.set(dropS, { x: rr * Math.cos(a), y: rr * Math.sin(a) * 0.55 });
    gsap.set(dropC, { x: -rr * Math.cos(a), y: -rr * Math.sin(a) * 0.55 });
    updateReelChrome(t);
  };

  const tl = gsap.timeline({ paused: true, onComplete: () => setTimeout(() => { if (reel) goSetup(); }, 700) });
  draw(0);
  tl.to({ v: 0 }, { v: 1, duration: REEL_END, ease: 'none', onUpdate() { draw(this.time()); } }, 0);
  tl.fromTo($('rlGrid'), { opacity: 0 }, { opacity: 1, duration: 0.8, ease: 'power2.out' }, 0);
  const slamNum = (el, at, out) => {
    tl.fromTo(el, { scale: 1.45, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.34, ease: 'power4.out' }, at);
    tl.to(el, { scale: 0.86, opacity: 0, duration: 0.12, ease: 'power2.in' }, out);
  };
  slamNum($('rlN50'), 0.85, 1.48);
  slamNum($('rlN20'), 1.5, 2.18);
  slamNum($('rlN4'), 2.2, 2.62);
  tl.fromTo($('rlSpark1'), { scale: 0, y: 0 }, { scale: 1, y: -620, duration: 0.5, ease: 'power3.out' }, 1.52);
  tl.to($('rlSpark1'), { scale: 0, duration: 0.25, ease: 'power2.in' }, 2.3);
  tl.fromTo($('rlWipePink'), { scale: 0, y: 760 }, { scale: 0.55, y: 0, duration: 0.5, ease: 'power3.out' }, 2.22);
  tl.to($('rlWipePink'), { scale: 13, duration: 0.55, ease: 'expo.in' }, 2.78);
  tl.fromTo($('rlWipeAmber'), { scale: 0 }, { scale: 13, duration: 0.55, ease: 'expo.inOut' }, 3.12);
  tl.set($('rlWipePink'), { opacity: 0 }, 3.9);
  slamNum($('rlN400'), 3.72, 4.52);
  slamNum($('rlN200'), 4.56, 5.2);
  tl.to($('rlWipeAmber'), { scale: 0, duration: 0.42, ease: 'expo.in' }, 5.12);
  const cupLine = $('rlCupLine');
  const CUP_LEN = cupLine.getTotalLength();
  tl.set(cupLine, { opacity: 1 }, 8.45);
  tl.fromTo(cupLine, { strokeDasharray: CUP_LEN, strokeDashoffset: CUP_LEN }, { strokeDashoffset: 0, duration: 0.75, ease: 'power3.inOut' }, 8.45);
  tl.fromTo($('rlSpark2'), { scale: 0, y: 0 }, { scale: 0.8, y: -560, duration: 0.45, ease: 'power3.out' }, 10.57);
  tl.to($('rlSpark2'), { scale: 0, duration: 0.2, ease: 'power2.in' }, 11.1);
  tl.fromTo($('rlSpark3'), { scale: 0, y: 0 }, { scale: 0.6, y: -700, duration: 0.45, ease: 'power3.out' }, 11.07);
  tl.to($('rlSpark3'), { scale: 0, duration: 0.2, ease: 'power2.in' }, 11.55);
  tl.to($('rlCupSvg'), { scale: 0.18, opacity: 0, transformOrigin: '540px 1060px', duration: 0.45, ease: 'power3.in' }, 11.38);
  tl.fromTo([dropS, dropC], { scale: 0 }, { scale: 1, duration: 0.5, ease: 'power3.out', stagger: 0.06 }, 11.72);
  tl.fromTo($('rlRip1'), { scale: 0.35, opacity: 0.9 }, { scale: 1.9, opacity: 0, duration: 0.95, ease: 'power2.out', immediateRender: false }, 12.9);
  tl.fromTo($('rlRip2'), { scale: 0.35, opacity: 0.7 }, { scale: 1.45, opacity: 0, duration: 0.95, ease: 'power2.out', immediateRender: false }, 13.04);
  [$('rlW1'), $('rlW2'), $('rlW3')].forEach((w, i) => {
    tl.fromTo(w, { yPercent: 105 }, { yPercent: 0, duration: 0.7, ease: 'expo.out' }, 13.0 + i * 0.09);
  });
  tl.fromTo($('rlWordEn'), { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.6, ease: 'expo.out' }, 13.5);
  tl.fromTo($('rlWorld'), { scale: 1 }, { scale: 1.04, duration: 2.6, ease: 'sine.inOut' }, 12.4);
  return tl;
}

/** 진행 막대와 장별 한 줄 설명. 장이 바뀔 때만 글을 갈아 끼우고 한 번 떠오르게 한다. */
function updateReelChrome(t) {
  if (!reel) return;
  const idx = reelChapterIndex(t);
  REEL_CHAPTERS.forEach((c, i) => {
    const end = REEL_CHAPTERS[i + 1]?.at ?? REEL_END;
    const bar = document.getElementById(`rlBar${i}`);
    if (bar) bar.style.width = `${Math.max(0, Math.min(1, (t - c.at) / (end - c.at))) * 100}%`;
  });
  if (idx === reel.chapter) return;
  reel.chapter = idx;
  const cap = document.getElementById('rlCap');
  document.getElementById('rlKick').textContent = REEL_CHAPTERS[idx].kick;
  document.getElementById('rlLine').textContent = REEL_CHAPTERS[idx].line;
  cap.classList.remove('in');
  void cap.offsetWidth;
  cap.classList.add('in');
}

// ---------- 하루 기준 ----------
function renderObSetup() {
  const ob = ui.onboarding;
  return `<div class="ob-copy setup-copy">
      <div class="kicker">하루 기준</div>
      <h1 class="ob-title static">얼마나 마실지<br>정해 두세요</h1>
      <p class="ob-caption">나중에 설정에서 언제든 바꿀 수 있어요.</p>
    </div>
    <section class="hero-card settings-card ob-setup-card">
      <div class="limit-figures">
        <div class="limit-figure"><img src="${DROP('sugar')}" alt=""><div><div class="stat-num">${ob.sugar}<small>g</small></div><div class="stat-label">당</div></div></div>
        <div class="limit-figure"><img src="${DROP('caffeine')}" alt=""><div><div class="stat-num" id="obCaffeineNum">${ob.caffeine}<small>mg</small></div><div class="stat-label">카페인</div></div></div>
      </div>
      <div class="control-label">당</div>
      <div class="segmented">${[25, 50, 100].map(v => `<button class="${ob.sugar === v ? 'on' : ''}" data-a="obSugar" data-v="${v}">${v} g</button>`).join('')}</div>
      <div class="control-label">카페인</div>
      <div class="slider-row"><span>100</span><input type="range" id="obCaffeine" min="100" max="600" step="25" value="${ob.caffeine}" aria-label="카페인 하루 기준"><span>600</span></div>
      <div class="card-note">기본값은 당 50 g(WHO 권고), 카페인 400 mg(식약처 성인 권고)이에요.</div>
    </section>
    <div class="ob-foot"><button class="cta" data-a="obFinish">시작</button></div>`;
}

function bindObSetup() {
  const slider = document.getElementById('obCaffeine');
  if (!slider) return;
  slider.oninput = () => {
    ui.onboarding.caffeine = Number(slider.value);
    document.getElementById('obCaffeineNum').innerHTML = `${slider.value}<small>mg</small>`;
  };
}

const ONBOARDING_ACTIONS = {
  // 누르면 다음 장 처음으로. 마지막 장이면 하루 기준으로.
  obNext: () => {
    if (!reel) return;
    const next = REEL_CHAPTERS[reelChapterIndex(reel.tl.time()) + 1];
    if (next) reel.tl.play(next.at);
    else goSetup();
  },
  obSkip: () => goSetup(),
  obSugar: v => { ui.onboarding.sugar = Number(v); },
  obFinish: () => {
    unmountReel();
    S.settings.sugarG = ui.onboarding.sugar;
    S.settings.caffeineMg = ui.onboarding.caffeine;
    S.onboarded = true;
    ui.onboarding = null;
    saveState();
  },
};
