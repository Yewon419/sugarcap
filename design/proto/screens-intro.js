'use strict';
// 로슈·카인 소개(2026-09-26 대표님 결정: 온보딩이 아니라 첫 마감 때, 모션그래픽으로).
// 온보딩 마지막 질문 "오늘의 분량을 남기면 어디로 가냐고요...?"의 답. 첫 먹이기 화면이 열리기 직전 한 번만 재생된다.
// 온보딩 릴과 같은 그림 언어(바탕 #F3F5F8, 번지는 원, 외곽선 글자, 방울 사진). 폰 좌표(402×874)로 바로 그린다.
// 장별 문구는 초안 — 대표님이 고친다. 캐릭터는 정지 그림이라 성격(로슈 경계·카인 엉뚱)은 몸짓으로만 흉내 낸다.

const INTRO_CHAPTERS = [
  { at: 0, line: '오늘 남긴 만큼은…' },
  { at: 1.6, line: '이 친구들에게 가요' },
  { at: 3.2, line: '로슈 · 남긴 당을 먹어요. 처음엔 낯을 가려요' },
  { at: 5.4, line: '카인 · 남긴 카페인을 먹어요. 좀 엉뚱해요' },
  { at: 7.6, line: '많이 남길수록 더 가까워져요' },
];
const INTRO_END = 10.0;
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

function mountIntro() {
  const el = document.createElement('div');
  el.className = 'intro';
  el.dataset.a = 'introNext';
  el.innerHTML = `
    <div class="in-bg"></div>
    <div class="in-grid"></div>
    <div class="in-wipe" id="inWipePink"></div>
    <div class="in-wipe" id="inWipeAmber"></div>
    <div class="in-wipe" id="inWipeCream"></div>
    <div class="in-night" id="inNight"></div>
    <div class="in-outline" id="inNameR">로슈</div>
    <div class="in-outline light" id="inNameK">카인</div>
    <i class="in-drop" id="inDropS" style="background-image:url('${DROP('sugar')}')"></i>
    <i class="in-drop" id="inDropC" style="background-image:url('${DROP('caffeine')}')"></i>
    <img class="in-char" id="inRoshu" src="${characterAsset('roshu')}" alt="로슈">
    <img class="in-char kain" id="inKain" src="${characterAsset('kain')}" alt="카인">
    <div class="in-bond" id="inBond"><div class="in-bond-name">처음 만난 사이</div><div class="bond-bar"><i id="inBondFill"></i></div></div>
    <div class="reel-progress">${INTRO_CHAPTERS.map((_, i) => `<i><b id="inBar${i}"></b></i>`).join('')}</div>
    <button class="reel-skip" data-a="introSkip">건너뛰기</button>
    <div class="reel-cap" id="inCap"><div class="reel-line" id="inLine"></div></div>
    <div class="in-cta" id="inCta"><button class="cta" data-a="introDone">먹이러 가기</button></div>`;
  document.getElementById('screen').appendChild(el);
  intro = { el, tl: buildIntroTimeline(el), chapter: -1 };
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) intro.tl.progress(1).pause();
  else intro.tl.play(0);
}

function buildIntroTimeline(root) {
  const $ = id => root.querySelector(`#${id}`);
  const tl = gsap.timeline({ paused: true, onUpdate: () => updateIntroChrome(tl.time()) });
  const X = 201;
  // 첫 상태: 모든 무대 요소는 fromTo가 잡는다(되감아도 같은 그림).
  // 1 · 방울 두 개가 떠오른다
  tl.fromTo($('inDropS'), { x: X - 92, y: 300, scale: 0 }, { scale: 1, duration: 0.55, ease: 'power3.out' }, 0.15);
  tl.fromTo($('inDropC'), { x: X + 8, y: 300, scale: 0 }, { scale: 1, duration: 0.55, ease: 'power3.out' }, 0.25);
  tl.to([$('inDropS'), $('inDropC')], { y: 288, duration: 0.6, ease: 'sine.inOut', yoyo: true, repeat: 1 }, 0.7);
  // 2 · 방울이 양옆 위로 갈라지고, 아래에서 둘이 솟아오른다
  tl.to($('inDropS'), { x: 64, y: 170, scale: 0.7, duration: 0.6, ease: 'power3.inOut' }, 1.6);
  tl.to($('inDropC'), { x: 254, y: 170, scale: 0.7, duration: 0.6, ease: 'power3.inOut' }, 1.62);
  tl.fromTo($('inRoshu'), { x: 40, y: 940, scale: 0.8, rotation: 0 }, { y: 360, duration: 0.7, ease: 'power3.out' }, 1.9);
  tl.fromTo($('inKain'), { x: 236, y: 960, scale: 0.8, rotation: 0 }, { y: 380, duration: 0.7, ease: 'power3.out' }, 2.02);
  // 3 · 로슈: 분홍이 번지고 가운데로. 비켜서 등을 돌렸다가 슬쩍 돌아본다(경계)
  tl.fromTo($('inWipePink'), { scale: 0 }, { scale: 16, duration: 0.6, ease: 'expo.inOut' }, 3.2);
  tl.to([$('inKain'), $('inDropC'), $('inDropS')], { opacity: 0, duration: 0.2, ease: 'power2.in' }, 3.3);
  tl.fromTo($('inNameR'), { scale: 1.25, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.5, ease: 'power4.out' }, 3.55);
  tl.to($('inRoshu'), { x: X - 105, y: 330, scale: 1.25, duration: 0.6, ease: 'power3.inOut' }, 3.3);
  // 뒷걸음질로 멀어졌다가(작아짐), 고개만 기울여 이쪽을 살핀다
  tl.to($('inRoshu'), { x: X + 10, y: 300, scale: 0.72, rotation: 8, duration: 0.5, ease: 'power2.out' }, 4.15);
  tl.to($('inRoshu'), { rotation: -7, duration: 0.35, ease: 'sine.inOut', yoyo: true, repeat: 1 }, 4.7);
  // 4 · 카인: 호박이 번지고, 폴짝 들어와 뜬금없이 한 바퀴
  tl.fromTo($('inWipeAmber'), { scale: 0 }, { scale: 16, duration: 0.6, ease: 'expo.inOut' }, 5.4);
  tl.to([$('inRoshu'), $('inNameR')], { opacity: 0, duration: 0.2, ease: 'power2.in' }, 5.5);
  tl.fromTo($('inNameK'), { scale: 1.25, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.5, ease: 'power4.out' }, 5.75);
  tl.fromTo($('inKain'), { x: -160, y: 420, scale: 1.3, opacity: 1, rotation: 0 },
    { x: X - 72, duration: 0.55, ease: 'power3.out', immediateRender: false }, 5.6);
  tl.to($('inKain'), { y: 330, duration: 0.25, ease: 'power2.out', yoyo: true, repeat: 1 }, 5.6);
  tl.to($('inKain'), { rotation: 360, duration: 0.9, ease: 'power3.inOut' }, 6.45);
  // 5 · 함께: 바탕이 돌아오고 나란히, "처음 만난 사이"
  tl.fromTo($('inWipeCream'), { scale: 0 }, { scale: 16, duration: 0.6, ease: 'expo.inOut' }, 7.6);
  tl.to($('inNameK'), { opacity: 0, duration: 0.2 }, 7.7);
  tl.set($('inKain'), { rotation: 0 }, 7.9);
  tl.fromTo($('inRoshu'), { x: 52, y: 330, scale: 0, opacity: 1, rotation: 0 },
    { scale: 1, duration: 0.5, ease: 'power3.out', immediateRender: false }, 8.0);
  tl.fromTo($('inKain'), { x: 226, y: 350, scale: 0, opacity: 1 },
    { scale: 1, duration: 0.5, ease: 'power3.out', immediateRender: false }, 8.08);
  tl.fromTo($('inBond'), { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: 0.45, ease: 'power3.out' }, 8.4);
  tl.fromTo($('inBondFill'), { width: '0%' }, { width: '10%', duration: 0.8, ease: 'power3.out' }, 8.6);
  // 6 · 밤으로, 먹이러 가기
  tl.fromTo($('inNight'), { opacity: 0 }, { opacity: 1, duration: 0.8, ease: 'power2.inOut' }, 9.2);
  tl.fromTo($('inBond'), { color: '#141a24' }, { color: '#ffffff', duration: 0.8, ease: 'power2.inOut', immediateRender: false }, 9.2);
  tl.fromTo($('inCta'), { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.45, ease: 'power3.out' }, 9.5);
  tl.set({}, {}, INTRO_END);
  return tl;
}

function updateIntroChrome(t) {
  if (!intro) return;
  INTRO_CHAPTERS.forEach((c, i) => {
    const end = INTRO_CHAPTERS[i + 1]?.at ?? INTRO_END;
    const bar = document.getElementById(`inBar${i}`);
    if (bar) bar.style.width = `${Math.max(0, Math.min(1, (t - c.at) / (end - c.at))) * 100}%`;
  });
  const idx = introChapterIndex(t);
  if (idx === intro.chapter) return;
  intro.chapter = idx;
  const cap = document.getElementById('inCap');
  document.getElementById('inLine').textContent = INTRO_CHAPTERS[idx].line;
  cap.classList.remove('in');
  void cap.offsetWidth;
  cap.classList.add('in');
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
