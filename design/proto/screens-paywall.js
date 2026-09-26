'use strict';
// 페이월(SPEC §6, 2026-09-26 개편). 추이·설정과 같은 캐주얼 그림 언어.
// 기능을 누르다 들어오면 그 기능을 먼저 말하고, 구매하면 그 기능으로 이어서 간다(탐색 규칙: 페이월은 기능 위로 닫힌다).
// 자동 갱신 구독이라 갱신·해지 안내와 약관·개인정보 링크, 구매 복원이 빠지면 심사에 걸린다.

// 기능을 누르다 들어왔을 때 첫 문장. "호감도·말걸기" 같은 기능 이름 대신 얻는 것을 말한다(대표님 문구).
const PAYWALL_LEADS = {
  affinity: '로슈, 카인과 더 친해질 수 있어요',
  month: '월 추이는 Pro에서 열려요',
  goal: '조금씩 줄이기는 Pro에서 열려요',
  delta: '지난주 대비는 Pro에서 열려요',
};

const PLANS = [
  { id: 'yearly', title: '연간', price: '₩9,900', note: '월 825원꼴 · 해지할 때까지 매년', badge: '추천' },
  { id: 'lifetime', title: '평생', price: '₩29,000', note: '한 번만 결제' },
];

/** 페이월을 연다. feature는 PAYWALL_LEADS 키 또는 null(설정의 "알아보기"처럼 특정 기능이 없을 때). */
function openPaywall(feature) {
  ui.paywall = { feature, plan: 'yearly' };
  ui.sheet = 'paywall';
}

function renderPaywall() {
  const pw = ui.paywall ?? { feature: null, plan: 'yearly' };
  const lead = pw.feature ? PAYWALL_LEADS[pw.feature] : '한 번 결제로 아래 기능이 모두 열려요';
  const plan = PLANS.find(p => p.id === pw.plan);
  const featureCard = (id, title, art) => `<div class="pw-feat ${pw.feature === id ? 'focus' : ''}"><div class="pw-art">${art}</div><div class="pw-feat-title">${title}</div></div>`;
  return `
    <div class="dim" data-a="closePaywall"></div>
    <div class="sheet pw-sheet">
      <div class="grabber"></div>
      <div class="sheet-head"><span class="kicker">SUGARCAP PRO</span><button class="text-button" data-a="closePaywall">닫기</button></div>
      <div class="scroll">
        <div class="pw-hero">
          <span class="pw-ring"></span><span class="pw-ring two"></span>
          <i class="pw-drop s" style="background-image:url('${DROP('sugar')}')"></i>
          <i class="pw-drop c" style="background-image:url('${DROP('caffeine')}')"></i>
        </div>
        <h2 class="pw-title">덜 마신 날을<br>더 잘 보이게</h2>
        <p class="pw-lead">${lead}</p>
        <div class="pw-feats">
          ${featureCard('affinity', '로슈·카인과 친해지기', `<img src="${characterAsset('roshu')}" alt=""><img class="kain" src="${characterAsset('kain')}" alt="">`)}
          ${featureCard('month', '월 추이', `<span class="pw-cal">${Array.from({ length: 12 }, (_, i) => `<i style="--s:${[0.9, 0.5, 0.7, 0.3, 1, 0.6, 0.8, 0.4, 0.95, 0.55, 0.75, 0.65][i]}"></i>`).join('')}</span>`)}
          ${featureCard('goal', '조금씩 줄이기', '<span class="pw-steps"><i style="--h:.9"></i><i style="--h:.72"></i><i style="--h:.56"></i><i style="--h:.4"></i></span>')}
          ${featureCard('widget', '위젯', `<span class="pw-widget"><b>4<small>g</small></b><i style="background-image:url('${DROP('sugar')}')"></i></span>`)}
        </div>
        <div class="pw-plans">${PLANS.map(p => `<button class="pw-plan ${p.id === pw.plan ? 'on' : ''}" data-a="pickPlan" data-v="${p.id}">
          ${p.badge ? `<span class="pw-badge">${p.badge}</span>` : ''}
          <div><div class="pw-plan-title">${p.title}</div><div class="pw-plan-note">${p.note}</div></div>
          <div class="pw-price">${p.price}</div></button>`).join('')}</div>
        <div style="height:190px"></div>
      </div>
      <div class="pw-foot">
        <button class="cta" data-a="buyPro">${plan.title}으로 시작</button>
        <p class="pw-legal">연간 구독은 기간이 끝나기 24시간 전에 해지하지 않으면 자동으로 갱신돼요. 해지는 App Store 계정 설정에서 해요.</p>
        <div class="pw-links"><button data-a="restorePro">구매 복원</button><span>·</span><button>이용약관</button><span>·</span><button>개인정보처리방침</button></div>
      </div>
    </div>`;
}

const PAYWALL_ACTIONS = {
  closePaywall: () => { ui.sheet = null; ui.paywall = null; },
  pickPlan: v => { ui.paywall.plan = v; },
  // 프로토타입 구매: Pro를 켜고, 누르다 온 기능으로 이어서 간다.
  buyPro: () => {
    const feature = ui.paywall?.feature;
    S.pro = true;
    saveState();
    ui.paywall = null;
    ui.sheet = null;
    if (feature === 'affinity') ui.sheet = 'affinity';
    if (feature === 'month') ui.trendRange = 'month';
  },
  restorePro: () => { ui.sheet = 'restoreDone'; ui.paywall = null; },
};
