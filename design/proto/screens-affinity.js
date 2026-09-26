'use strict';
// 호감도(Pro). 2026-09-26 대표님 확정: A 초상 바탕 + 말걸기. 표정 칸은 뺐다.
//  - 단계 숫자·점수는 보이지 않는다. 사이 이름과 진행 막대만(SPEC §4.8).
//  - 말걸기: 캐릭터마다 하루 한 번. 선택지 3개 중 하나를 고르면 캐릭터가 말 대신 몸짓으로 반응한다.
//    대화하면 호감도가 조금(TALK_POINTS) 오른다. 먹이기(하루 1~10점)를 앞지르지 않는 크기.
//  - 성격(대표님 설정): 로슈는 처음엔 낯가리다 가까워질수록 애교가 확확 는다.
//    카인은 무슨 생각인지 모르겠지만 엉뚱하고 귀엽다. 둘 다 말은 못 하고 반응만 한다.
// 대사는 초안이다. 대표님이 고친다.

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
 * 반응 = [몸짓, 묘사]. 로슈는 사이 단계에 따라 세 갈래(낯가림 1~3 · 풀림 4~6 · 애교 7~10).
 * 몸짓 이름은 style.css의 .react-* 애니메이션.
 */
const ROSHU_REACTIONS = {
  shy: {
    greet: ['duck', '로슈가 눈을 피하며 꾸벅해요.'],
    praise: ['hide', '로슈가 볼이 발개져서 몸을 반쯤 숨겨요.'],
    pat: ['freeze', '로슈가 움찔했다가… 가만히 있어요.'],
    walk: ['shake', '로슈가 고개를 도리도리 저어요. 아직은 부끄러운가 봐요.'],
    ask: ['fidget', '로슈가 날개를 꼼지락꼼지락해요.'],
    five: ['duck', '로슈가 날개를 들다 말고 슬쩍 내려요.'],
  },
  warm: {
    greet: ['wave', '로슈가 날개를 작게 흔들어요.'],
    praise: ['proud', '로슈가 뿌듯한 듯 몸을 쭉 펴요.'],
    pat: ['lean', '로슈가 눈을 감고 머리를 쏙 내밀어요.'],
    walk: ['hop', '로슈가 쪼르르 와서 옆에 서요.'],
    ask: ['flap', '로슈가 신나서 날개를 파닥파닥해요.'],
    five: ['bounce', '로슈가 톡, 날개를 맞대요.'],
  },
  sweet: {
    greet: ['jump', '로슈가 달려와서 폭 안겨요!'],
    praise: ['spin', '로슈가 빙글빙글 돌며 좋아해요.'],
    pat: ['nuzzle', '로슈가 손에 머리를 부비부비해요.'],
    walk: ['waddle', '로슈가 벌써 앞장서서 뒤뚱뒤뚱 걸어가요.'],
    ask: ['lean', '로슈가 몸을 폭 기대고 꾸벅꾸벅 졸아요.'],
    five: ['jump', '로슈가 두 날개로 짝! 하이파이브해요.'],
  },
};

/** 카인은 단계와 상관없이 엉뚱하다. 가까워질수록 끝에 다정한 한 줄이 붙는다. */
const KAIN_REACTIONS = {
  greet: ['spin', '카인이 한쪽 눈으로 가만히 쳐다보다가… 갑자기 한 바퀴 돌아요.'],
  praise: ['peck', '카인이 부리로 바닥을 톡톡 두드려요. 칭찬인 줄 아는 걸까요?'],
  pat: ['dodge', '카인이 머리를 내밀었다가 갑자기 딴 데를 봐요.'],
  walk: ['wander', '카인이 반대쪽으로 세 걸음 갔다가 돌아와요.'],
  ask: ['tilt', '카인이 고개를 옆으로 꺾어요. 끝까지 꺾어요.'],
  five: ['peck', '카인이 부리로 손바닥을 콕 찍어요.'],
};
const KAIN_WARM_TAIL = ['', ' 그리고 옆에 슬쩍 와서 앉아요.', ' 그러고는 발 위에 딱 붙어 앉아요.'];

function stageBucket(level) {
  if (level <= 3) return 0;
  if (level <= 6) return 1;
  return 2;
}

function reactionFor(side, choiceId, level) {
  const bucket = stageBucket(level);
  if (side === 'sugar') return ROSHU_REACTIONS[['shy', 'warm', 'sweet'][bucket]][choiceId];
  const [move, line] = KAIN_REACTIONS[choiceId];
  return [move, line + KAIN_WARM_TAIL[bucket]];
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
        <p class="talk-line">${esc(talk.line)}</p>
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
