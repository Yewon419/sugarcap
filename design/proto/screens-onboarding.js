'use strict';
// 온보딩(2026-09-26 대표님 요청): 모션그래픽 소개 영상처럼 저절로 흘러가는 네 장면 + 하루 기준 설정.
// 장면: 컵 → 기록(컵이 줄어듦) → 밤에 먹이기 → 가까워지는 사이 → 하루 기준.
// 조작: 화면 누르기 = 다음 장면, 건너뛰기 = 하루 기준으로. 모션 줄이기면 움직임 없이 장면만 바뀐다.
// 장면 안의 움직임은 CSS 애니메이션(onboarding.css), 숫자 세기·컵 바꾸기 같은 값 변화만 JS 타이머로 한다.

const OB_SCENES = [
  { id: 'cup', duration: 3400 },
  { id: 'record', duration: 4400 },
  { id: 'feed', duration: 4600 },
  { id: 'bond', duration: 4200 },
];
const OB_SETUP = OB_SCENES.length;
let obTimers = [];

const obReduce = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

function obClearTimers() {
  obTimers.forEach(clearTimeout);
  obTimers = [];
}

/** 장면 시작 기준으로 ms 뒤에 실행. 장면을 넘기면 모두 취소된다. */
function obAt(ms, fn) {
  obTimers.push(setTimeout(fn, obReduce() ? 0 : ms));
}

function obStart() {
  ui.onboarding = { scene: 0, sugar: S.settings.sugarG, caffeine: S.settings.caffeineMg };
}

function obSetScene(scene) {
  obClearTimers();
  ui.onboarding.scene = scene;
  ui.onboarding.ran = null;
}

/** 타이머가 장면을 넘길 때. 클릭으로 넘길 때는 obSetScene만 하고 그리기는 handleClick에 맡긴다. */
function obGo(scene) {
  obSetScene(scene);
  render();
}

/** 장면이 그려진 뒤: 진행 막대를 채우고, 값 변화를 걸고, 끝나면 다음 장면으로. */
function obRunScene() {
  const ob = ui.onboarding;
  if (!ob || ob.scene >= OB_SETUP) return;
  // 같은 장면에서 다시 그려져도(1분 갱신 등) 타이머를 겹쳐 걸지 않는다.
  if (ob.ran === ob.scene) return;
  ob.ran = ob.scene;
  const scene = OB_SCENES[ob.scene];
  const bar = document.querySelector(`.ob-progress i[data-i="${ob.scene}"] b`);
  if (bar) {
    bar.style.transition = `width ${obReduce() ? 0 : scene.duration}ms linear`;
    requestAnimationFrame(() => { bar.style.width = '100%'; });
  }
  OB_EFFECTS[scene.id]?.();
  obAt(scene.duration, () => obGo(ob.scene + 1));
}

// ---------- 장면별 값 변화 ----------
function obSetCup(set, step) {
  const layer = document.querySelector('.ob-cup');
  if (!layer) return;
  const img = new Image();
  img.src = cupAsset(set, step);
  img.className = 'ob-cup-img fade-in';
  layer.appendChild(img);
  setTimeout(() => { while (layer.children.length > 1) layer.firstElementChild.remove(); }, 500);
}

function obCount(el, from, to, ms) {
  if (!el) return;
  if (obReduce()) { el.textContent = num(to); return; }
  const start = performance.now();
  const tick = t => {
    const p = Math.min(1, (t - start) / ms);
    const eased = 1 - (1 - p) ** 3;
    el.textContent = num(Math.round(from + (to - from) * eased));
    if (p < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

const OB_EFFECTS = {
  record: () => {
    const number = document.getElementById('obNumber');
    obAt(1300, () => { obSetCup('strawberry-latte', 40); obCount(number, 50, 20, 700); });
    obAt(2700, () => { obSetCup('strawberry-latte', 10); obCount(number, 20, 4, 600); });
  },
  feed: () => {
    obAt(1500, () => document.querySelector('.ob-cup')?.classList.add('shake'));
    obAt(1650, () => obSetCup('strawberry-latte', 0));
    obAt(3000, () => document.getElementById('obRoshu')?.classList.add('gulp'));
  },
  bond: () => {
    const names = ['처음 만난 사이', '반가운 사이', '단짝 사이'];
    const el = document.getElementById('obStage');
    names.forEach((name, i) => obAt(700 + i * 1000, () => {
      if (!el) return;
      el.classList.remove('tick');
      void el.offsetWidth;
      el.textContent = name;
      el.classList.add('tick');
    }));
  },
};

// ---------- 그리기 ----------
/** 글자를 줄 단위로 가려 두었다가 아래에서 밀어 올린다. */
function obLines(lines, startMs, gapMs = 140) {
  return lines.map((line, i) =>
    `<span class="ob-line"><span style="animation-delay:${startMs + i * gapMs}ms">${line}</span></span>`).join('');
}

function renderOnboarding() {
  const ob = ui.onboarding;
  afterRender.push(obRunScene);
  const progress = `<div class="ob-progress">${OB_SCENES.map((_, i) =>
    `<i data-i="${i}"><b style="width:${i < ob.scene ? '100%' : '0'}"></b></i>`).join('')}</div>`;
  if (ob.scene >= OB_SETUP) {
    afterRender.push(bindObSetup);
    return `<div class="onboard setup">${renderObSetup()}</div>`;
  }
  const id = OB_SCENES[ob.scene].id;
  return `<div class="onboard scene-${id}" data-a="obNext">
    ${OB_RENDER[id]()}
    ${progress}
    <button class="ob-skip" data-a="obSkip">건너뛰기</button>
  </div>`;
}

const OB_RENDER = {
  cup: () => `
    <div class="ob-cup rise"><img class="ob-cup-img" src="${cupAsset('strawberry-latte', 100)}" alt=""></div>
    <div class="ob-copy">
      <div class="kicker ob-fade" style="animation-delay:250ms">슈가캡</div>
      <h1 class="ob-title">${obLines(['오늘 마실 당을', '컵에 담아 드려요'], 450)}</h1>
      <p class="ob-caption ob-fade" style="animation-delay:1100ms">하루 기준 50 g이 가득 찬 컵으로 하루가 시작돼요.</p>
    </div>`,
  record: () => `
    <div class="ob-cup"><img class="ob-cup-img" src="${cupAsset('strawberry-latte', 100)}" alt=""></div>
    <div class="ob-copy">
      <div class="kicker ob-fade">기록</div>
      <h1 class="ob-title">${obLines(['마실 때마다', '컵이 줄어요'], 150)}</h1>
      <div class="ob-number ob-fade" style="animation-delay:500ms"><span id="obNumber">50</span><small>g</small><em>남은 당</em></div>
    </div>
    <div class="ob-chip fly" style="animation-delay:700ms"><img src="../assets/drops/sugar.png" alt="">메가MGC커피 · 딸기 라떼 <b>30 g</b></div>
    <div class="ob-chip fly two" style="animation-delay:2100ms"><img src="../assets/drops/sugar.png" alt="">스타벅스 · 바닐라 라떼 <b>16 g</b></div>`,
  feed: () => `
    <div class="ob-cup"><img class="ob-cup-img" src="${cupAsset('strawberry-latte', 10)}" alt=""></div>
    <div class="ob-night"></div>
    <div class="ob-copy light">
      <div class="kicker ob-fade">밤에</div>
      <h1 class="ob-title">${obLines(['남은 만큼', '로슈에게 먹여요'], 250)}</h1>
    </div>
    <img class="ob-drop" src="../assets/drops/sugar.png" alt="">
    <div class="ob-roshu"><div class="ob-bubble">냠, 4 g</div><img id="obRoshu" src="${characterAsset('roshu')}" alt="로슈"></div>`,
  bond: () => `
    <div class="ob-copy">
      <div class="kicker ob-fade">사이</div>
      <h1 class="ob-title">${obLines(['덜 마신 날일수록', '둘과 가까워져요'], 150)}</h1>
    </div>
    <div class="ob-pair">
      <div class="ob-friend"><img class="pop" style="animation-delay:500ms" src="${characterAsset('roshu')}" alt="로슈"><span>로슈 · 당</span></div>
      <div class="ob-friend"><img class="pop spin-later" style="animation-delay:700ms" src="${characterAsset('kain')}" alt="카인"><span>카인 · 카페인</span></div>
    </div>
    <div class="ob-stage-box ob-fade" style="animation-delay:600ms">
      <div class="ob-stage" id="obStage">처음 만난 사이</div>
      <div class="bond-bar"><i class="ob-bond-fill"></i></div>
    </div>`,
};

function renderObSetup() {
  const ob = ui.onboarding;
  return `<div class="ob-copy setup-copy">
      <div class="kicker">하루 기준</div>
      <h1 class="ob-title static">얼마나 마실지<br>정해 두세요</h1>
      <p class="ob-caption">나중에 설정에서 언제든 바꿀 수 있어요.</p>
    </div>
    <section class="hero-card settings-card ob-setup-card">
      <div class="limit-figures">
        <div class="limit-figure"><img src="../assets/drops/sugar.png" alt=""><div><div class="stat-num">${ob.sugar}<small>g</small></div><div class="stat-label">당</div></div></div>
        <div class="limit-figure"><img src="../assets/drops/caffeine.png" alt=""><div><div class="stat-num" id="obCaffeineNum">${ob.caffeine}<small>mg</small></div><div class="stat-label">카페인</div></div></div>
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
  obNext: () => {
    if (ui.onboarding.scene < OB_SETUP) obSetScene(ui.onboarding.scene + 1);
  },
  obSkip: () => obSetScene(OB_SETUP),
  obSugar: v => { ui.onboarding.sugar = Number(v); },
  obFinish: () => {
    obClearTimers();
    S.settings.sugarG = ui.onboarding.sugar;
    S.settings.caffeineMg = ui.onboarding.caffeine;
    S.onboarded = true;
    ui.onboarding = null;
    saveState();
  },
};
