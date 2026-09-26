'use strict';
// 설정 탭. 추이 확정안(캐주얼)과 같은 문법: 흰 유리 카드, 큰 숫자, 기존 그림(방울·캐릭터).
// 규칙은 SPEC §4.4·§9.5: 당 기준 프리셋 25·50·100 g, 카페인 100~600 mg,
// 감소 목표(Pro)가 도는 동안은 그 쪽 하루 기준을 목표가 관리한다(직접 못 바꿈).

const LIMIT_SOURCE = { sugar: 'WHO 권고', caffeine: '식약처 권고' };
const LIMIT_DEFAULT = { sugar: 50, caffeine: 400 };
const GOAL_TARGETS = { sugar: [40, 30, 25, 20], caffeine: [300, 250, 200, 150] };
const GOAL_STEP = { sugar: 5, caffeine: 25 };
const GOAL_WEEKS = [4, 8, 12];

const goalOf = side => S.goals?.[side] ?? null;

/** 그 주의 하루 기준 = 시작 − 폭 × 달성한 주. 단위로 반올림하되 정확히 중간이면 목표 쪽으로(§9.5). */
function goalWeekLimit(goal, side) {
  const perWeek = (goal.start - goal.target) / goal.weeks;
  const raw = goal.start - perWeek * goal.achieved;
  const unit = GOAL_STEP[side];
  const lower = Math.floor(raw / unit) * unit;
  const value = raw - lower > unit / 2 ? lower + unit : lower;
  return Math.max(goal.target, value);
}

function renderSettings() {
  return `<div class="trends casual settings-page">
    <div class="trend-head"><div class="date-label">설정</div></div>
    ${limitsCard()}
    ${goalsCard()}
    ${timeCard()}
    ${proCard()}
    ${etcCard()}
    <div class="version-note">슈가캡 1.0 · HTML 프로토타입</div>
  </div>`;
}

function limitsCard() {
  const figure = side => {
    const meta = SIDES[side];
    const goal = goalOf(side);
    return `<div class="limit-figure">
      <img src="../assets/drops/${side}.png" alt="">
      <div>
        <div class="stat-num">${num(limitOf(side))}<small>${meta.unit}</small></div>
        <div class="stat-label">${meta.label} · ${goal ? '줄이기 진행 중' : limitOf(side) === LIMIT_DEFAULT[side] ? LIMIT_SOURCE[side] : '지금 기준'}</div>
      </div>
    </div>`;
  };
  const sugarGoal = goalOf('sugar');
  const caffeineGoal = goalOf('caffeine');
  const sugarControl = sugarGoal
    ? `<div class="managed">${ICON.lock} 줄이기 목표가 당 기준을 맡고 있어요</div>`
    : `<div class="segmented">${[25, 50, 100].map(v =>
      `<button class="${S.settings.sugarG === v ? 'on' : ''}" data-a="setSugar" data-v="${v}">${v} g</button>`).join('')}</div>`;
  const caffeineControl = caffeineGoal
    ? `<div class="managed">${ICON.lock} 줄이기 목표가 카페인 기준을 맡고 있어요</div>`
    : `<div class="slider-row"><span>100</span>
        <input type="range" id="caffeineSlider" min="100" max="600" step="25" value="${S.settings.caffeineMg}" aria-label="카페인 하루 기준">
        <span>600</span></div>`;
  return `<section class="hero-card settings-card">
    <div class="kicker">하루 기준</div>
    <div class="limit-figures">${figure('sugar')}${figure('caffeine')}</div>
    <div class="control-label">당</div>${sugarControl}
    <div class="control-label">카페인</div>${caffeineControl}
    <div class="card-note">기본값은 당 50 g(WHO 권고), 카페인 400 mg(식약처 성인 권고)이에요.</div>
  </section>`;
}

function goalsCard() {
  const row = side => {
    const meta = SIDES[side];
    const goal = goalOf(side);
    if (goal) {
      return `<div class="goal-row">
        <img class="goal-char ${side}" src="${characterAsset(meta.char)}" alt="">
        <div class="goal-text">
          <div class="goal-title">${meta.label} 조금씩 줄이기</div>
          <div class="goal-sub">이번 주 ${num(goalWeekLimit(goal, side))} ${meta.unit} → 목표 ${num(goal.target)} ${meta.unit} · ${goal.weeks}주 중 ${goal.achieved}주 달성</div>
          <div class="bond-bar small"><i style="width:${Math.round((goal.achieved / goal.weeks) * 100)}%"></i></div>
        </div>
        <button class="text-button" data-a="askStopGoal" data-v="${side}">그만두기</button>
      </div>`;
    }
    return `<div class="goal-row">
      <img class="goal-char ${side}" src="${characterAsset(meta.char)}" alt="">
      <div class="goal-text">
        <div class="goal-title">${meta.label} 조금씩 줄이기</div>
        <div class="goal-sub">4~12주에 걸쳐 하루 기준을 낮춰요</div>
      </div>
      <button class="goal-start" data-a="openGoal" data-v="${side}">${S.pro ? '시작' : `${ICON.lock} Pro`}</button>
    </div>`;
  };
  return `<section class="shelf settings-card">
    <div class="shelf-head"><span class="kicker">조금씩 줄이기</span></div>
    ${row('sugar')}${row('caffeine')}
    <div class="card-note">한 주에 5일 이상 기준 안이면 다음 주 기준이 조금 내려가요. 못 지킨 주는 그대로예요.</div>
  </section>`;
}

function timeCard() {
  const boundary = Array.from({ length: 7 }, (_, h) => h);
  const close = [18, 19, 20, 21, 22, 23];
  const option = (h, selected) => `<option value="${h}" ${h === selected ? 'selected' : ''}>${h < 12 ? '오전' : '오후'} ${h % 12 || 12}시</option>`;
  return `<section class="shelf settings-card">
    <div class="shelf-head"><span class="kicker">시간</span></div>
    <label class="time-row"><span>하루가 바뀌는 시각</span>
      <select id="boundarySelect">${boundary.map(h => option(h, S.settings.boundary)).join('')}</select></label>
    <label class="time-row"><span>오늘 마감을 여는 시각</span>
      <select id="closeSelect">${close.map(h => option(h, S.settings.closeFrom)).join('')}</select></label>
    <div class="card-note">하루가 바뀌는 시각 전에 마신 음료는 전날 몫으로 들어가요.</div>
  </section>`;
}

function proCard() {
  if (S.pro) {
    return `<section class="stat-row single"><div class="stat-card pro-on">
      <div class="pro-chars"><img src="${characterAsset('roshu')}" alt=""><img src="${characterAsset('kain')}" alt=""></div>
      <div><div class="goal-title">슈가캡 Pro 사용 중</div><div class="stat-label">호감도·말걸기·월 추이·조금씩 줄이기</div></div>
    </div></section>`;
  }
  return `<section class="stat-row single"><button class="stat-card pro-promo" data-a="paywall">
    <div class="pro-chars"><img src="${characterAsset('roshu')}" alt=""><img src="${characterAsset('kain')}" alt=""></div>
    <div><div class="goal-title">슈가캡 Pro</div><div class="stat-label">호감도와 말걸기, 월 추이, 조금씩 줄이기</div></div>
    <span class="pro-go">알아보기</span>
  </button></section>`;
}

function etcCard() {
  const row = (label, action, trailing) => `<button class="etc-row" data-a="${action}">${label}<span>${trailing}</span></button>`;
  return `<section class="shelf settings-card etc">
    ${row('앱 소개 다시 보기', 'replayOnboarding', '›')}
    ${row('구매 복원', 'restore', '')}
    ${row('개인정보처리방침', 'openLink', '↗')}
    ${row('문의하기', 'openLink', '↗')}
  </section>`;
}

// ---------- 감소 목표 시트 ----------
function renderGoalSheet() {
  const side = ui.goalDraft.side;
  const meta = SIDES[side];
  const current = limitOf(side);
  const targets = GOAL_TARGETS[side].filter(t => t < current);
  const draft = ui.goalDraft;
  draft.target ??= targets[Math.floor(targets.length / 2)] ?? null;
  const perWeek = draft.target ? (current - draft.target) / draft.weeks : 0;
  return `<div class="dim light" data-a="closeSheet"></div>
  <div class="sheet glass">
    <div class="grabber"></div>
    <div class="sheet-head"><span class="kicker">${meta.label} 조금씩 줄이기</span><button class="text-button" data-a="closeSheet">닫기</button></div>
    <div class="scroll">
      <h2 class="sheet-headline">어디까지<br>줄여 볼까요?</h2>
      <div class="caption-note">지금 하루 기준은 ${num(current)} ${meta.unit}이에요.</div>
      ${targets.length ? `
      <div class="kicker section-gap tight">목표</div>
      <div class="chip-row wrap">${targets.map(t => `<button class="chip ${draft.target === t ? 'on' : ''}" data-a="goalTarget" data-v="${t}">${t} ${meta.unit}</button>`).join('')}</div>
      <div class="kicker section-gap tight">기간</div>
      <div class="pad-x"><div class="segmented">${GOAL_WEEKS.map(w => `<button class="${draft.weeks === w ? 'on' : ''}" data-a="goalWeeks" data-v="${w}">${w}주</button>`).join('')}</div></div>
      <div class="goal-preview">
        <img src="${characterAsset(meta.char)}" alt="">
        <div>주마다 약 <b>${num(perWeek)} ${meta.unit}</b>씩 내려가서<br>${draft.weeks}주 뒤 하루 <b>${num(draft.target)} ${meta.unit}</b>가 돼요.</div>
      </div>
      <div class="pad-x"><button class="cta" data-a="startGoal">시작</button></div>`
      : '<div class="caption-note">이미 가장 낮은 기준이에요.</div>'}
      <div class="bottom-space"></div>
    </div>
  </div>`;
}

/** 그만두기 확인. 브라우저 확인 창 대신 앱 안의 작은 시트로 묻는다. */
function renderStopGoal() {
  const side = ui.stopGoalSide;
  return `<div class="dim" data-a="closePanel2"></div>
  <div class="panel-sheet glass confirm">
    <div class="panel-title">${SIDES[side].label} 줄이기를 그만둘까요?</div>
    <p class="caption-note" style="padding:8px 0 16px">지금까지 달성한 주 기록이 사라지고, 하루 기준은 이번 주 값으로 남아요.</p>
    <button class="cta danger" data-a="stopGoal">그만두기</button>
    <button class="cta ghost" data-a="closePanel2">계속하기</button>
  </div>`;
}

const SETTINGS_ACTIONS = {
  setSugar: v => { S.settings.sugarG = Number(v); saveState(); },
  openGoal: v => {
    if (!S.pro) { ui.sheet = 'paywall'; return; }
    ui.goalDraft = { side: v, weeks: 8, target: null };
    ui.sheet = 'goal';
  },
  goalTarget: v => { ui.goalDraft.target = Number(v); },
  goalWeeks: v => { ui.goalDraft.weeks = Number(v); },
  startGoal: () => {
    const { side, target, weeks } = ui.goalDraft;
    S.goals ??= {};
    S.goals[side] = { start: limitOf(side), target, weeks, achieved: 0, startDay: dayKey(now()) };
    saveState();
    ui.sheet = null;
  },
  askStopGoal: v => { ui.stopGoalSide = v; },
  closePanel2: () => { ui.stopGoalSide = null; },
  stopGoal: () => {
    delete S.goals[ui.stopGoalSide];
    ui.stopGoalSide = null;
    saveState();
  },
  replayOnboarding: () => { obStart(); },
  restore: () => { ui.sheet = 'restoreDone'; },
  openLink: () => {},
};

/** 설정 화면이 그려진 뒤 입력 컨트롤을 묶는다. */
function bindSettingsControls() {
  const slider = document.getElementById('caffeineSlider');
  if (slider) {
    slider.oninput = () => {
      S.settings.caffeineMg = Number(slider.value);
      const figure = document.querySelectorAll('.limit-figure .stat-num')[1];
      if (figure) figure.innerHTML = `${slider.value}<small>mg</small>`;
    };
    slider.onchange = () => { saveState(); render(); };
  }
  const bind = (id, key) => {
    const el = document.getElementById(id);
    if (el) el.onchange = () => { S.settings[key] = Number(el.value); saveState(); render(); };
  };
  bind('boundarySelect', 'boundary');
  bind('closeSelect', 'closeFrom');
}
