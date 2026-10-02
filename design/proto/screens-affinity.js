'use strict';
// 호감도(Pro). 단계 숫자·점수는 보이지 않는다. 사이 이름과 진행 막대만(SPEC §4.8).
// 2026-10-03 대표님: 말걸기를 빼고 캐릭터 하나만 둔다. 건드리면 몸짓으로 반응하고,
// 이어서 여러 번 건드리면 특이한 반응이 한 번 나온다. 점수는 주지 않는다.
//  - 성격(대표님 설정): 로슈는 처음엔 낯가리다 가까워질수록 애교가 확확 는다(낯가림은 부끄럼이 아니라 경계).
//    카인은 무슨 생각인지 모르겠지만 엉뚱하고 귀엽다.
// 몸짓 이름은 애니메이션 파일 이름이 되고, 지금은 style.css의 .react-* 로 자리만 채운다.
// 앱은 `PokeMath`(같은 간격·횟수).

const POKE_COMBO_WINDOW_MS = 600;
const POKE_COMBO_COUNT = 5;
const KAIN_REACTIONS = ['tilt', 'spin', 'hop'];

function pokeReaction(side, level, combo) {
  if (side === 'sugar') {
    if (combo >= POKE_COMBO_COUNT) return 'squish';
    return level <= 3 ? 'wary' : level <= 6 ? 'happy' : 'aegyo';
  }
  if (combo >= POKE_COMBO_COUNT) return 'flip';
  return KAIN_REACTIONS[Math.floor(Math.random() * KAIN_REACTIONS.length)];
}

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

// ---------- 동작 ----------
const AFFINITY_ACTIONS = {
  affinitySide: v => { ui.affinitySide = v; ui.poke = null; },
  poke: () => {
    const side = affinitySide();
    const t = Date.now();
    const last = ui.poke;
    const combo = last && t - last.at <= POKE_COMBO_WINDOW_MS && last.combo < POKE_COMBO_COUNT ? last.combo + 1 : 1;
    const move = pokeReaction(side, levelOf(S.points[SIDES[side].char]), combo);
    ui.poke = { at: t, combo };
    afterRender.push(() => {
      const el = document.getElementById('portraitChar');
      if (!el || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
      el.classList.add(`react-${move}`);
    });
  },
};

// ---------- 그리기 ----------
function renderAffinity() {
  const side = affinitySide();
  const meta = SIDES[side];
  const a = affinityOf(side);

  return `
    <div class="dim light" data-a="closeSheet"></div>
    <div class="sheet glass">
      <div class="grabber"></div>
      <div class="sheet-head"><span class="kicker">호감도</span><button class="text-button" data-a="closeSheet">닫기</button></div>
      <div class="scroll">
        <div class="segmented inset-x">${SIDE_ORDER.map(s =>
          `<button class="${s === side ? 'on' : ''}" data-a="affinitySide" data-v="${s}">${SIDES[s].name}</button>`).join('')}</div>
        <div class="portrait">
          <img class="portrait-char ${side}" id="portraitChar" src="${characterAsset(meta.char)}" alt="${meta.name} 건드리기" role="button" data-a="poke">
          <div class="portrait-with">${meta.withGwa}</div>
          <h2 class="portrait-stage">${a.stage}</h2>
          <div class="bond-bar"><i style="width:${Math.round(a.progress * 100)}%"></i></div>
          <div class="bond-note">${a.next ? `다음은 ${a.next}` : '가장 가까운 사이가 됐어요'}</div>
        </div>
        <div class="bottom-space"></div>
      </div>
    </div>`;
}
