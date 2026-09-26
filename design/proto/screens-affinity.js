'use strict';
// 호감도(Pro). 2026-09-26 대표님 확정: A 초상 바탕 + 말걸기. 표정 칸은 뺐다.
//  - 단계 숫자·점수는 보이지 않는다. 사이 이름과 진행 막대만(SPEC §4.8).
//  - 말걸기: 캐릭터마다 하루 한 번. 선택지 3개 중 하나를 고르면 캐릭터가 말 대신 몸짓으로 반응한다.
//    대화하면 호감도가 조금(TALK_POINTS) 오른다. 먹이기(하루 1~10점)를 앞지르지 않는 크기.
//  - 성격(대표님 설정): 로슈는 처음엔 낯가리다 가까워질수록 애교가 확확 는다.
//    카인은 무슨 생각인지 모르겠지만 엉뚱하고 귀엽다. 둘 다 말은 못 하고 반응만 한다.
// 반응은 캐릭터마다 애니메이션 3개(대표님 제작)와 짧은 한마디뿐이다.

const TALK_POINTS = 2;

/** 내가 건넬 수 있는 말·행동. 날마다 3개씩 고른다. */
const TALK_CHOICES = [
  { id: 'greet', text: '안녕, 좋은 밤' },
  { id: 'praise', text: '오늘 잘 참았어' },
  { id: 'pat', text: '머리 쓰다듬기' },
  { id: 'walk', text: '같이 산책 갈래?' },
  { id: 'ask', text: '오늘 뭐 했어?' },
  { id: 'five', text: '하이파이브' },
];

/**
 * 반응 애니메이션은 대표님이 캐릭터마다 3개씩(모두 6개) 그린다(2026-09-26). 긴 지문 대신 짧은 한마디만.
 * 몸짓 이름은 애니메이션 파일 이름이 되고, 지금은 style.css의 .react-* 로 자리만 채운다.
 *  - 로슈: 사이 단계로 정해진다. 경계(1~3) → 좋아함(4~6) → 애교(7~10). 낯가림은 부끄럼이 아니라 경계다(대표님).
 *  - 카인: 엉뚱해서 무엇을 고르든 셋 중 하나가 나온다(같은 날·같은 선택이면 같은 반응).
 */
const ROSHU_REACTIONS = [
  ['wary', '경계해요'],
  ['happy', '좋아해요'],
  ['aegyo', '애교를 부려요'],
];
const KAIN_REACTIONS = [
  ['tilt', '고개를 갸웃해요'],
  ['spin', '갑자기 한 바퀴 돌아요'],
  ['hop', '폴짝 뛰어요'],
];

function reactionFor(side, choiceId, level) {
  if (side === 'sugar') {
    const bucket = level <= 3 ? 0 : level <= 6 ? 1 : 2;
    return ROSHU_REACTIONS[bucket];
  }
  const seed = [...`${dayKey(now())}${choiceId}`].reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) >>> 0, 11);
  return KAIN_REACTIONS[seed % KAIN_REACTIONS.length];
}

/** 오늘의 선택지 3개. 날짜와 캐릭터로 정해져서 다시 열어도 같다. */
function todaysChoices(side) {
  const seed = [...`${dayKey(now())}${side}`].reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) >>> 0, 7);
  const pool = [...TALK_CHOICES];
  const picked = [];
  let h = seed;
  while (picked.length < 3) {
    h = (h * 1103515245 + 12345) >>> 0;
    picked.push(pool.splice(h % pool.length, 1)[0]);
  }
  return picked;
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
  affinitySide: v => { ui.affinitySide = v; },
  talk: v => {
    const side = affinitySide();
    const char = SIDES[side].char;
    const today = dayKey(now());
    S.talks ??= {};
    if (S.talks[char]?.day === today) return;
    const before = levelOf(S.points[char]);
    const [move, line] = reactionFor(side, v, before);
    S.points[char] += TALK_POINTS;
    const after = levelOf(S.points[char]);
    S.talks[char] = { day: today, choice: v, move, line, leveledUp: after > before };
    saveState();
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
  const talk = S.talks?.[meta.char];
  const talkedToday = talk?.day === dayKey(now());
  const choices = todaysChoices(side);

  const talkBlock = talkedToday
    ? `<div class="talk-result">
        <div class="talk-said">"${esc(TALK_CHOICES.find(c => c.id === talk.choice).text)}"</div>
        <p class="talk-line">${meta.withIga} ${esc(talk.line)}</p>
        <div class="talk-foot">${talk.leveledUp ? `${meta.withGwa} ${a.stage}가 됐어요.` : '조금 더 가까워졌어요.'} 내일 또 말 걸어 주세요.</div>
      </div>`
    : `<div class="talk-ask">${meta.name}에게 뭐라고 할까요?</div>
      <div class="talk-choices">${choices.map(c => `<button class="talk-choice" data-a="talk" data-v="${c.id}">${esc(c.text)}</button>`).join('')}</div>
      <div class="caption-note" style="padding:10px 0 0">${meta.name}는 말은 못 하지만 몸으로 대답해요. 하루에 한 번 말 걸 수 있어요.</div>`;

  return `
    <div class="dim light" data-a="closeSheet"></div>
    <div class="sheet glass">
      <div class="grabber"></div>
      <div class="sheet-head"><span class="kicker">호감도</span><button class="text-button" data-a="closeSheet">닫기</button></div>
      <div class="scroll">
        <div class="segmented inset-x">${SIDE_ORDER.map(s =>
          `<button class="${s === side ? 'on' : ''}" data-a="affinitySide" data-v="${s}">${SIDES[s].name}</button>`).join('')}</div>
        <div class="portrait">
          <img class="portrait-char ${side}" id="portraitChar" src="${characterAsset(meta.char)}" alt="${meta.name}">
          <div class="portrait-with">${meta.withGwa}</div>
          <h2 class="portrait-stage">${a.stage}</h2>
          <div class="bond-bar"><i style="width:${Math.round(a.progress * 100)}%"></i></div>
          <div class="bond-note">${a.next ? `다음은 ${a.next}` : '가장 가까운 사이가 됐어요'}</div>
        </div>
        <div class="kicker section-gap">말 걸기</div>
        <div class="talk">${talkBlock}</div>
        <div class="bottom-space"></div>
      </div>
    </div>`;
}
