'use strict';
// 로슈·카인 소개(2026-09-26 대표님 결정: 온보딩이 아니라 첫 마감 때, 모션그래픽으로).
// 온보딩 마지막 질문 "오늘의 분량을 남기면 어디로 가냐고요...?"의 답. 첫 먹이기 화면이 열리기 직전 한 번만 재생된다.
// 온보딩 릴과 같은 1080×1920 무대를 폰 화면에 줄여 쓴다(REEL_SCALE·REEL_OFFSET_X). 글씨는 설명 카드 대신 무대 위 큰 글자.
// 첫 장(남긴 방울이 어디로 가나)은 대표님 요청으로 살렸다. 나머지 세 장은 대표님 문구 세 줄. 캐릭터는 정지 그림이라 몸짓(튀기·떨기·돌기)은 transform으로 흉내 낸다.

// 첫 장 뒤의 세 장은 한 타임라인(child)으로 짜고 INTRO_OPEN만큼 밀어 붙인다. INTRO_NIGHT_AT은 그 child 기준 시각.
const INTRO_OPEN = 2.6;
const INTRO_CHAPTERS = [
  { at: 0, lines: ['오늘 남긴 만큼은', '이 친구들에게 가요'] },
  { at: INTRO_OPEN, lines: ['달달한 걸', '좋아하는'], name: '로슈!' },
  { at: INTRO_OPEN + 3.7, lines: ['카페인을', '좋아하는'], name: '카인!' },
  { at: INTRO_OPEN + 7.3, lines: ['많이많이 남겨서', '두 친구와', '더 가까워져요'] },
];
const INTRO_END = INTRO_OPEN + 11;
const INTRO_NIGHT_AT = 10.2;
// 마지막 장에 쏟아지는 방울: [가로 위치(무대 가운데 기준), 종류]. 당은 로슈, 카페인은 카인에게 간다.
const INTRO_RAIN = [[-260, 'sugar'], [220, 'caffeine'], [-60, 'sugar'], [380, 'caffeine'], [-400, 'sugar'], [80, 'caffeine'], [-180, 'sugar'],
  [300, 'caffeine'], [-330, 'sugar'], [140, 'caffeine'], [-20, 'sugar'], [420, 'caffeine'], [-120, 'sugar'], [260, 'caffeine']];
let intro = null; // { el, tl, chapter }

function introChapterIndex(t) {
  let i = 0;
  INTRO_CHAPTERS.forEach((c, k) => { if (t >= c.at) i = k; });
  return i;
}

/** render()가 부른다: ui.intro가 켜져 있으면 소개 층을 띄운다(다시 그리기 밖의 별도 층). */
function syncIntro() {
  if (ui.intro && !intro) mountIntro();
  if (!ui.intro && intro) unmountIntro();
}

function unmountIntro() {
  if (!intro) return;
  intro.tl.kill();
  intro.el.remove();
  intro = null;
}

function introText(id, chapter, cls) {
  const line = s => `<span class="it-mask"><span>${s}</span></span>`;
  return `<div class="it-text ${cls}" id="${id}">${chapter.lines.map(line).join('')}${chapter.name ? `<span class="it-mask it-name"><span>${chapter.name}</span></span>` : ''}</div>`;
}

function mountIntro() {
  const el = document.createElement('div');
  el.className = 'intro';
  el.dataset.a = 'introNext';
  const [c0, c1, c2, c3] = INTRO_CHAPTERS;
  el.innerHTML = `
    <div class="reel-stage" style="transform: translateX(${REEL_OFFSET_X}px) scale(${REEL_SCALE})">
      <div class="it-bg"></div>
      <svg class="it-layer" id="itGrid" viewBox="0 0 1080 1920" aria-hidden="true"></svg>
      <div class="it-group" id="itG0">
        ${introText('itT0', c0, 'small')}
        <i class="it-drop mid" id="itOpS" style="background-image:url('${DROP('sugar')}')"></i>
        <i class="it-drop mid" id="itOpC" style="background-image:url('${DROP('caffeine')}')"></i>
      </div>
      <div class="it-ripple" id="itRip1"></div><div class="it-ripple" id="itRip2"></div>
      <div class="it-group" id="itG1">
        <div class="it-panel pink" id="itPink"></div>
        <svg class="it-layer" viewBox="0 0 1080 1920" aria-hidden="true"><g id="itBurst"></g></svg>
        <img class="it-char roshu" id="itRoshu1" src="${characterAsset('roshu')}" alt="">
        ${[0, 1, 2].map(i => `<i class="it-drop small" id="itOrbit${i}" style="background-image:url('${DROP('sugar')}')"></i>`).join('')}
        ${introText('itT1', c1, '')}
      </div>
      <i class="it-drop big" id="itDropS" style="background-image:url('${DROP('sugar')}')"></i>
      <div class="it-group" id="itG2">
        <div class="it-panel amber" id="itAmber"></div>
        <svg class="it-layer" viewBox="0 0 1080 1920" aria-hidden="true">
          <g id="itRingG"><circle id="itRing" cx="540" cy="1250" r="360" fill="none" stroke="#3b1d0e" stroke-width="40" stroke-linecap="round"/></g>
          <g id="itTicks"></g>
        </svg>
        <img class="it-char kain" id="itKain2" src="${characterAsset('kain')}" alt="">
        <i class="it-drop mid" id="itDropC" style="background-image:url('${DROP('caffeine')}')"></i>
        ${introText('itT2', c2, '')}
      </div>
      <div class="it-group" id="itG3">
        <div class="it-panel cream" id="itCream"></div>
        <div class="it-night" id="itNight"></div>
        ${INTRO_RAIN.map(([, side], i) => `<i class="it-drop rain" id="itRain${i}" style="background-image:url('${DROP(side)}')"></i>`).join('')}
        <img class="it-char roshu" id="itRoshu3" src="${characterAsset('roshu')}" alt="">
        <img class="it-char kain" id="itKain3" src="${characterAsset('kain')}" alt="">
        ${introText('itT3', c3, 'small')}
        <div class="it-bond" id="itBond"><div class="it-bond-name">처음 만난 사이</div><div class="it-bond-bar"><i id="itBondFill"></i></div></div>
      </div>
    </div>
    <div class="reel-progress">${INTRO_CHAPTERS.map((_, i) => `<i><b id="inBar${i}"></b></i>`).join('')}</div>
    <button class="reel-skip" data-a="introSkip">건너뛰기</button>
    <div class="in-cta" id="inCta"><button class="cta" data-a="introDone">먹이러 가기</button></div>`;
  document.getElementById('screen').appendChild(el);
  intro = { el, tl: buildIntroTimeline(el), chapter: -1 };
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) intro.tl.progress(1).pause();
  else intro.tl.play(0);
}

function buildIntroTimeline(root) {
  const $ = id => root.querySelector(`#${id}`);
  const NS = 'http://www.w3.org/2000/svg';
  const E = { o3: gsap.parseEase('power3.out'), i2: gsap.parseEase('power2.in'), io3: gsap.parseEase('power3.inOut'), lin: v => v };
  const clamp01 = v => Math.max(0, Math.min(1, v));
  const seg = (t, a, b, ease = E.lin) => ease(clamp01((t - a) / (b - a)));
  const lerp = (a, b, k) => a + (b - a) * k;

  // 모눈(릴과 같은 세로선)
  [180, 360, 540, 720, 900].forEach((x, i) => {
    const l = document.createElementNS(NS, 'line');
    l.setAttribute('x1', x); l.setAttribute('x2', x); l.setAttribute('y1', 0); l.setAttribute('y2', 1920);
    l.setAttribute('stroke', '#141a24'); l.setAttribute('stroke-width', i === 2 ? 2 : 1.2); l.setAttribute('opacity', '0.1');
    $('itGrid').appendChild(l);
  });
  // 로슈 착지 때 튀는 점
  const burst = Array.from({ length: 14 }, (_, i) => {
    const c = document.createElementNS(NS, 'circle');
    c.setAttribute('fill', i % 2 ? '#ffffff' : '#141a24');
    $('itBurst').appendChild(c);
    return { c, a: (i / 14) * Math.PI * 2 + 0.2, d: 300 + (i % 3) * 70 };
  });
  // 카인 시계 링의 눈금
  for (let i = 0; i < 60; i += 1) {
    const l = document.createElementNS(NS, 'line');
    const long = i % 5 === 0;
    l.setAttribute('x1', 540); l.setAttribute('x2', 540); l.setAttribute('y1', 1250 - 420); l.setAttribute('y2', 1250 - (long ? 468 : 446));
    l.setAttribute('stroke', '#f3f5f8'); l.setAttribute('stroke-width', long ? 6 : 3); l.setAttribute('stroke-linecap', 'round');
    l.setAttribute('transform', `rotate(${i * 6} 540 1250)`);
    $('itTicks').appendChild(l);
  }
  const RING_C = 2 * Math.PI * 360;
  $('itRing').setAttribute('stroke-dasharray', `${RING_C} ${RING_C}`);

  // 가로는 무대 가운데 기준(xPercent -50), 세로는 윗변 기준
  gsap.set(root.querySelectorAll('.it-char, .it-drop'), { xPercent: -50 });
  const orbit = [0, 1, 2].map(i => $(`itOrbit${i}`));
  const rain = INTRO_RAIN.map(([x, side], i) => ({ el: $(`itRain${i}`), x, side, at: 8.2 + i * 0.1 }));
  const HIT = 0.5;
  const roshu3 = $('itRoshu3'), kain3 = $('itKain3'), dropC = $('itDropC');

  const draw = t => {
    // 1장: 로슈 주위를 도는 당 방울 세 개
    const orbOn = seg(t, 2.05, 2.4, E.o3);
    orbit.forEach((el, i) => {
      const a = (t - 2.05) * 3.1 + (i * Math.PI * 2) / 3;
      const depth = Math.sin(a);
      gsap.set(el, { x: 360 * Math.cos(a), y: 1300 + 120 * depth - 55, scale: orbOn * (0.8 + 0.25 * depth), zIndex: depth > 0 ? 3 : 1 });
    });
    burst.forEach(p => {
      const k = seg(t, 1.9, 2.5, E.o3);
      p.c.setAttribute('cx', (540 + Math.cos(p.a) * p.d * k).toFixed(1));
      p.c.setAttribute('cy', (1320 + Math.sin(p.a) * p.d * k * 0.8).toFixed(1));
      p.c.setAttribute('r', (t < 1.9 ? 0 : 20 * (1 - seg(t, 2.1, 2.55))).toFixed(1));
    });
    // 2장: 커피 방울이 오른쪽에서 통통 튀어와 카인에게 들어간다
    const kb = seg(t, 4.55, 5.25);
    gsap.set(dropC, {
      x: lerp(760, 0, kb),
      y: 1080 - 520 * Math.abs(Math.sin(Math.PI * kb * 2.5)) * (1 - kb),
      scale: t < 4.55 ? 0 : 1 - seg(t, 5.15, 5.3),
    });
    let v = seg(t, 5.25, 5.8, E.o3);
    $('itRing').setAttribute('stroke-dashoffset', (RING_C * (1 - v)).toFixed(1));
    $('itRing').style.opacity = v > 0 ? '1' : '0'; // 둥근 끝이 길이 0에서도 점으로 찍힌다
    $('itRingG').setAttribute('transform', `rotate(${-90 + 140 * seg(t, 5.25, 7.3, E.io3)} 540 1250)`);
    $('itTicks').setAttribute('transform', `rotate(${-(t - 5.25) * 30} 540 1250)`);
    $('itTicks').style.opacity = seg(t, 5.3, 5.7).toFixed(3);
    // 3장: 방울이 쏟아져 둘에게 들어갈 때마다 둘이 가까워진다
    let nS = 0, nC = 0, hopS = 0, hopC = 0;
    const enter = seg(t, 7.65, 8.15, E.o3);
    const pos = { sugar: 0, caffeine: 0 };
    rain.forEach(r => {
      const got = seg(t, r.at + HIT, r.at + HIT + 0.3, E.o3);
      const hop = t > r.at + HIT ? Math.exp(-(t - r.at - HIT) * 9) : 0;
      if (r.side === 'sugar') { nS += got; hopS += hop; } else { nC += got; hopC += hop; }
    });
    pos.sugar = lerp(-1000, -270, enter) + 100 * (nS / 7);
    pos.caffeine = lerp(1000, 270, enter) - 100 * (nC / 7);
    gsap.set(roshu3, { x: pos.sugar, y: 1040 - 46 * Math.min(1, hopS) });
    gsap.set(kain3, { x: pos.caffeine, y: 1110 - 46 * Math.min(1, hopC) });
    rain.forEach(r => {
      const k = seg(t, r.at, r.at + HIT, E.i2);
      const target = pos[r.side];
      gsap.set(r.el, {
        x: lerp(r.x * 0.8, target, k),
        y: lerp(780, r.side === 'sugar' ? 1200 : 1240, k) - 260 * Math.sin(Math.PI * k),
        scale: t < r.at ? 0 : seg(t, r.at, r.at + 0.12, E.o3) * (1 - seg(t, r.at + HIT - 0.06, r.at + HIT + 0.04)),
      });
    });
  };

  const tl = gsap.timeline();
  draw(0);
  tl.to({ v: 0 }, { v: 1, duration: INTRO_END - INTRO_OPEN, ease: 'none', onUpdate() { draw(this.time()); } }, 0);

  const reveal = (id, at) => tl.fromTo(root.querySelectorAll(`#${id} .it-mask > span`), { yPercent: 108 },
    { yPercent: 0, duration: 0.6, ease: 'power4.out', stagger: 0.09 }, at);
  const hide = (id, at) => tl.to(root.querySelectorAll(`#${id} .it-mask > span`), { yPercent: -108, duration: 0.3, ease: 'power3.in', stagger: 0.04 }, at);
  const circle = (r, x, y) => `circle(${r}px at ${x}px ${y}px)`;

  // ---- 1장 · 달달한 걸 좋아하는 로슈!
  tl.fromTo($('itDropS'), { x: 0, y: -320, scaleX: 1, scaleY: 1 }, { y: 1080, duration: 0.5, ease: 'power2.in' }, 0.1);
  tl.to($('itDropS'), { scaleY: 0.66, scaleX: 1.3, duration: 0.09, ease: 'power2.out', yoyo: true, repeat: 1 }, 0.6);
  [$('itRip1'), $('itRip2')].forEach((el, i) =>
    tl.fromTo(el, { scale: 0.2, opacity: 0.9 }, { scale: 2.6 + i, opacity: 0, duration: 0.9, ease: 'power2.out', immediateRender: false }, 0.6 + i * 0.1));
  tl.fromTo($('itPink'), { clipPath: circle(0, 540, 1190) }, { clipPath: circle(2300, 540, 1190), duration: 0.75, ease: 'expo.inOut' }, 0.7);
  tl.to($('itDropS'), { scale: 0, duration: 0.3, ease: 'power2.in' }, 0.95);
  reveal('itT1', 1.05);
  tl.fromTo($('itRoshu1'), { x: 0, y: 2000, scaleX: 1, scaleY: 1, rotation: 0 }, { y: 1060, duration: 0.6, ease: 'back.out(1.5)' }, 1.35);
  tl.to($('itRoshu1'), { scaleY: 0.88, scaleX: 1.1, duration: 0.1, ease: 'power2.out', yoyo: true, repeat: 1 }, 1.9);
  tl.to($('itRoshu1'), { rotation: -7, duration: 0.3, ease: 'sine.inOut', yoyo: true, repeat: 3 }, 2.4);

  // ---- 2장 · 카페인을 좋아하는 카인! (호박 면이 밀려 올라오고, 1장은 위로 밀려난다)
  hide('itT1', 3.45);
  tl.to($('itG1'), { y: -700, duration: 0.65, ease: 'power4.inOut' }, 3.65);
  tl.fromTo($('itAmber'), { y: 1920 }, { y: 0, duration: 0.65, ease: 'power4.inOut' }, 3.65);
  reveal('itT2', 4.1);
  tl.fromTo($('itKain2'), { x: -900, y: 1060, rotation: 0 }, { x: 0, duration: 0.55, ease: 'power3.out' }, 4.15);
  tl.fromTo($('itKain2'), { y: 1060 }, { y: 880, duration: 0.27, ease: 'power2.out', yoyo: true, repeat: 1, immediateRender: false }, 4.15);
  tl.to($('itKain2'), { x: 18, duration: 0.045, ease: 'none', yoyo: true, repeat: 9 }, 5.3);
  tl.to($('itKain2'), { rotation: 360, duration: 0.8, ease: 'power3.inOut' }, 5.85);
  tl.fromTo($('itKain2'), { scale: 1 }, { scale: 1.08, duration: 0.2, ease: 'power2.out', yoyo: true, repeat: 1, immediateRender: false }, 6.65);

  // ---- 3장 · 많이많이 남겨서 두 친구와 더 가까워져요
  hide('itT2', 7.05);
  tl.fromTo($('itCream'), { clipPath: circle(0, 540, 1250) }, { clipPath: circle(2300, 540, 1250), duration: 0.7, ease: 'expo.inOut' }, 7.25);
  reveal('itT3', 7.85);
  tl.fromTo($('itBond'), { opacity: 0, y: 30 }, { opacity: 1, y: 0, duration: 0.5, ease: 'power3.out' }, 9.75);
  tl.fromTo($('itBondFill'), { width: '0%' }, { width: '10%', duration: 0.8, ease: 'power3.out' }, 9.95);
  tl.fromTo($('itNight'), { opacity: 0 }, { opacity: 1, duration: 0.8, ease: 'power2.inOut' }, INTRO_NIGHT_AT);
  tl.fromTo([$('itT3'), $('itBond')], { color: '#141a24' }, { color: '#ffffff', duration: 0.8, ease: 'power2.inOut', immediateRender: false }, INTRO_NIGHT_AT);
  tl.fromTo($('inCta'), { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.45, ease: 'power3.out' }, 10.45);

  // ---- 첫 장 · 오늘 남긴 만큼은 이 친구들에게 가요
  // 당 방울은 위로 날아가 로슈 장에서 떨어지고, 커피 방울은 오른쪽으로 빠졌다가 카인 장에서 튀어 들어온다.
  const master = gsap.timeline({ paused: true, onUpdate: () => updateIntroChrome(master.time()) });
  const opS = $('itOpS'), opC = $('itOpC');
  const opLines = root.querySelectorAll('#itT0 .it-mask > span');
  master.fromTo(opS, { x: -120, y: 1000, scale: 0 }, { scale: 1, duration: 0.5, ease: 'back.out(1.8)' }, 0.15);
  master.fromTo(opC, { x: 120, y: 1000, scale: 0 }, { scale: 1, duration: 0.5, ease: 'back.out(1.8)' }, 0.27);
  master.to([opS, opC], { y: 950, duration: 0.42, ease: 'sine.inOut', yoyo: true, repeat: 1, stagger: 0.12 }, 0.75);
  master.fromTo(opLines[0], { yPercent: 108 }, { yPercent: 0, duration: 0.6, ease: 'power4.out' }, 0.35);
  master.fromTo(opLines[1], { yPercent: 108 }, { yPercent: 0, duration: 0.6, ease: 'power4.out' }, 1.15);
  master.to(opLines, { yPercent: -108, duration: 0.3, ease: 'power3.in', stagger: 0.04 }, 2.05);
  master.to(opS, { y: -400, duration: 0.45, ease: 'power3.in' }, 2.1);
  master.to(opC, { x: 900, duration: 0.45, ease: 'power3.in' }, 2.18);
  master.add(tl, INTRO_OPEN);
  return master;
}

function updateIntroChrome(t) {
  if (!intro) return;
  INTRO_CHAPTERS.forEach((c, i) => {
    const end = INTRO_CHAPTERS[i + 1]?.at ?? INTRO_END;
    const bar = document.getElementById(`inBar${i}`);
    if (bar) bar.style.width = `${clamp01Intro((t - c.at) / (end - c.at)) * 100}%`;
  });
  intro.el.classList.toggle('night', t >= INTRO_OPEN + INTRO_NIGHT_AT + 0.3);
}

function clamp01Intro(v) {
  return Math.max(0, Math.min(1, v));
}

function finishIntro() {
  const pending = ui.intro;
  S.metFriends = true;
  saveState();
  ui.intro = null;
  unmountIntro();
  openFeeding(pending.kind, pending.day, pending.noDrink);
}

const INTRO_ACTIONS = {
  introNext: () => {
    if (!intro) return;
    const next = INTRO_CHAPTERS[introChapterIndex(intro.tl.time()) + 1];
    intro.tl.play(next ? next.at : INTRO_END);
  },
  introSkip: () => { if (intro) intro.tl.progress(1).pause(); },
  introDone: () => finishIntro(),
};
