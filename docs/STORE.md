# App Store 제출 자료 (Phase 4 초안)

앱 레코드: `슈가캡`, Bundle ID `com.sugarcap.app`, ASC 앱 ID `6814832068`.
이 파일은 초안이다. 확정 전에는 App Store Connect에 그대로 붙여 넣지 말고 대표님이 문구를 한 번 읽는다.

## 1. 기본 정보

| 항목 | 값 | 제한 |
|---|---|---|
| 이름 | 슈가캡 | 30자 |
| 부제 | 오늘 마신 당과 카페인 | 30자 |
| 기본 언어 | 한국어 | |
| 카테고리 | 건강 및 피트니스 (2차: 음식 및 음료) | |
| 연령 등급 | 4+ | |
| 가격 | 무료 + 앱 내 구입 | |

영문 병기(`SugarCap`) 여부는 SPEC §9-2로 남아 있다. 이름 칸에 병기하면 30자 안에 들어가지만
검색 노출과 브랜드 인상이 갈리므로 대표님 결정이 필요하다.

## 2. 키워드 (100자, 쉼표 구분, 공백 없이)

```
당,설탕,당류,카페인,커피,음료,기록,다이어트,건강,줄이기,스타벅스,메가커피,컴포즈,이디야,투썸
```

앱 이름과 부제에 이미 들어간 단어는 키워드에 다시 넣지 않아도 검색에 잡힌다.
브랜드명은 상표라 심사에서 걸릴 수 있다. 걸리면 브랜드명을 빼고 일반 단어로 채운다.

## 3. 프로모션 텍스트 (170자, 심사 없이 수정 가능)

```
하루치 당과 카페인이 담긴 컵이 마실 때마다 줄어듭니다. 밤에 남은 만큼을 로슈와 카인에게 먹여 주세요. 카페 8곳 메뉴 1,300여 개가 들어 있어 탭 두 번이면 기록이 끝납니다.
```

## 4. 설명 (4,000자)

```
슈가캡은 당과 카페인을 "줄이는" 기록 앱입니다.

■ 마실수록 줄어드는 컵
하루 기준만큼 채워진 컵으로 하루가 시작됩니다. 음료를 기록하면 그만큼 컵이 줄어듭니다.
얼마나 더 마실 수 있는지가 숫자가 아니라 눈에 보입니다.

■ 밤에 남은 만큼을 먹여 주세요
하루를 마감하면 남은 당은 로슈가, 남은 카페인은 카인이 먹습니다.
덜 마신 날일수록 많이 먹고, 그만큼 더 친해집니다. 많이 마신 날에도 잔소리는 없습니다.

■ 카페 메뉴 1,300여 개
스타벅스, 투썸플레이스, 이디야커피, 메가MGC커피, 컴포즈커피, 빽다방, 더벤티, 감성커피.
브랜드를 고르고 음료를 고르면 당과 카페인이 그대로 들어갑니다.
브랜드가 공개한 값만 씁니다. 공개하지 않은 값은 "미공개"로 남기고 지어내지 않습니다.
카페 메뉴에 없는 음료는 직접 입력할 수 있습니다.

■ 하루 기준은 내가 정합니다
기본값은 당 50 g(WHO 하루 권고), 카페인 400 mg(식약처 성인 하루 권고)입니다.
추이 화면에서 바꿀 수 있고, 하루가 바뀌는 시각도 설정에서 새벽 4시처럼 생활에 맞게 옮길 수 있습니다.

■ 추이
일주일 동안 날마다 얼마나 남겼는지 잔으로 봅니다.

■ 슈가캡 Pro
- 추이 월 보기와 지난주 대비
- 감소 목표: 하루 기준을 몇 주에 걸쳐 조금씩 낮춥니다. 한 주에 5일 이상 지키면 다음 주 기준이 내려가고, 못 지킨 주는 기준을 그대로 둡니다.
- 위젯

■ 계정도 서버도 없습니다
가입하지 않습니다. 기록은 이 기기에만 저장되고 어디로도 전송되지 않습니다.

구입 정보
- 슈가캡 Pro 연간: 자동 갱신 구독. 기간이 끝나기 24시간 전에 해지하지 않으면 자동으로 갱신됩니다. 해지는 기기의 App Store 계정 설정에서 합니다.
- 슈가캡 Pro 평생: 한 번만 결제하는 비소모성 상품입니다.
```

자동 갱신 구독을 팔면 설명에 갱신·해지 안내와 약관·개인정보 링크가 있어야 심사에서 걸리지 않는다.

## 5. 지원·정책 URL

| 항목 | 값 | 상태 |
|---|---|---|
| 지원 URL | https://sugarcap.vercel.app/ | 배포됨(2026-09-24). `site/index.html` |
| 마케팅 URL | (선택) | |
| 개인정보처리방침 URL | https://sugarcap.vercel.app/privacy/ | 배포됨(2026-09-24). `site/privacy/index.html` |

`site/`는 Vercel 프로젝트 `sugarcap`(팀 yewon419s-projects)에 정적 배포한다. 갱신은 `site/`에서
`npx vercel --prod --yes`. git 자동 배포는 안 걸려 있다. 카탈로그 원격 갱신(SPEC §2.3)도 같은 호스팅을 쓴다.

## 6. 앱 개인정보(App Privacy) 문항

수집하는 데이터가 없다. 문항에는 이렇게 답한다.

| 질문 | 답 |
|---|---|
| 이 앱이 데이터를 수집합니까? | **아니요** |
| 서드파티 SDK 포함 여부 | 없음(분석·광고·크래시 리포트 모두 없음) |
| 추적(App Tracking Transparency) | 하지 않음 → `NSUserTrackingUsageDescription` 불필요 |

근거: 앱은 네트워크로 카탈로그 JSON만 내려받고(읽기 전용), 사용자 기록은 기기 안 SwiftData에만 있다.
**서드파티 SDK나 분석 도구를 하나라도 넣는 순간 이 답이 거짓이 된다.**

## 7. 연령 등급 문항

전 항목 "없음"으로 답하면 4+가 나온다. 술·담배·약물 묘사 없음, 의학·치료 정보 없음, 사용자 생성 콘텐츠 없음,
웹 브라우징 없음, 도박 없음.

주의: 앱이 의학적 조언을 한다고 읽히면 심사와 등급이 달라진다. 화면 문구는 "권고 기준"만 적고
진단·치료·효능을 말하지 않는다.

## 8. 심사 정보

- 데모 계정: 불필요(로그인 없음).
- 연락처: 대표님 이름·전화·이메일.
- 심사 메모(초안):
  ```
  계정과 서버가 없는 로컬 기록 앱입니다. 모든 기능은 로그인 없이 바로 쓸 수 있습니다.
  카페 메뉴의 당·카페인 수치는 각 브랜드가 공식 홈페이지에 공개한 값을 그대로 옮긴 것이며,
  브랜드가 공개하지 않은 값은 "미공개"로 표시합니다.
  앱 내 구입은 슈가캡 Pro 1종(연간 구독 / 평생)이며 무료 기능만으로도 기록과 마감이 모두 가능합니다.
  ```

## 9. 스크린샷

CI(`iOS` 워크플로)가 6.9인치 시뮬레이터로 찍어 `store-screenshots` 아티팩트로 올린다.
데모 기록이 들어간 상태로 찍히며, 그 데이터는 Debug 빌드 전용 코드(`DemoData`)라 출시 빌드에는 없다.

| 파일 | 화면 |
|---|---|
| `01-today.png` | 오늘 화면(컵이 절반쯤 줄어든 상태) |
| `02-trends.png` | 추이 |
| `03-feeding.png` | 오늘 마감·먹이기 |
| `04-paywall.png` | 슈가캡 Pro |

App Store는 6.9인치 세트 하나면 나머지 크기를 자동으로 채운다.
문구를 얹은 마케팅용 이미지가 필요하면 이 원본 위에 따로 만든다.

## 10. 제출 전 체크리스트

- [x] 인앱 구매 상품 2개 등록 + "제출 준비 중" 상태 (`com.sugarcap.app.pro.yearly` ASC 6815455990, `com.sugarcap.app.pro.lifetime` ASC 6815458455). 2026-09-24 가격(₩9,900 / ₩29,000, 기준 KRW)·판매 지역 175개·한국어 현지화·심사용 스크린샷(페이월)·심사 메모까지 채움. **"심사에 추가"는 아직 안 누름** — 첫 구독·첫 비소모성 상품은 새 앱 버전과 함께 제출해야 하므로 1.0 제출 때 같이 누른다.
- [x] 구독 그룹 `SugarCap Pro`(ID 22409029) + 한국어 표시 이름 "슈가캡 Pro" (2026-09-24)
- [ ] 샌드박스 계정으로 구매·복원 확인 (SPEC §8 Phase 3 게이트)
- [x] 개인정보처리방침 URL 열림 확인 (2026-09-24, 200)
- [x] 지원 URL 열림 확인 (2026-09-24, 200)
- [ ] 스크린샷 5장 업로드
- [ ] 앱 개인정보 문항 제출
- [ ] 연령 등급 문항 제출
- [ ] 수출 규정: `ITSAppUsesNonExemptEncryption = false` (이미 Info.plist에 있음)
- [ ] KIPRIS 상표 확인 (SPEC §9-1, 아직 미확인)
- [x] 빌드 버전 정리: `MARKETING_VERSION` 1.0 (2026-09-24, `docs/RELEASE.md` 버전 절). 빌드 번호는 CI `run_number`, 심사 후보 1.0 (59)

## 11. 영어(미국) 현지화 (SPEC §9.9 ③ 초안)

ASC에서 "English (U.S.)" 현지화를 추가하고 아래를 넣는다. 한국어 현지화는 그대로 둔다.
앱은 기기 지역이 미국이면 미국 메뉴(Starbucks·Dutch Bros, `data/catalog-us.json` 467종)를 연다.
글자 수는 스크립트로 셌다(부제 30/30, 키워드 100/100, 프로모션 166/170).

| 항목 | 값 |
|---|---|
| 이름 | SugarCap |
| 부제 | Sugar and caffeine, by the cup |
| 개인정보처리방침 URL | https://sugarcap.vercel.app/en/privacy/ (`site/en/privacy/index.html`, 2026-10-08 배포, 200 확인). 앱 페이월 링크도 화면 언어가 한국어가 아니면 이 주소 |
| 지원 URL | https://sugarcap.vercel.app/ (한국어 페이지. 영어 지원 페이지는 미정) |
| 가격 | 연간 $9.99, 평생 $29.99(대표님 2026-10-08). ASC API로 미국만 수동 지정, 기준 지역은 KOR 그대로, 다른 나라는 자동 환산. 조회로 반영 확인 |

키워드:
```
sugar,caffeine,coffee,drink,tracker,log,diet,cut back,limit,starbucks,dutch bros,latte,energy,health
```
브랜드명은 한국어 키워드와 같은 이유로 심사에서 걸릴 수 있다. 걸리면 빼고 일반 단어로 채운다.

프로모션 텍스트:
```
Your daily cup of sugar and caffeine shrinks with every drink. At night, feed what's left to Roshu and Kain. 460+ Starbucks and Dutch Bros drinks, logged in two taps.
```

설명:
```
SugarCap is a log for cutting back on sugar and caffeine.

■ A cup that empties as you drink
Your day starts with a cup filled to your daily limit. Every drink you log takes its share out of the cup.
You see how much you have left, not just a number.

■ Feed what's left at night
When you close the day, Roshu eats the sugar you have left and Kain eats the caffeine.
The less you drink, the more they eat, and the closer you become. No scolding on the days you drink more.

■ 460+ cafe drinks
Starbucks and Dutch Bros, by cup size.
Pick a brand and a drink, and the sugar and caffeine go straight in.
We only use values the brand publishes. Anything a brand doesn't publish stays "Not published". We never make numbers up.
Sizes published only in fluid ounces are shown in milliliters.
For drinks that aren't on the menu, use manual entry.

■ You set the daily limit
Defaults are 50 g of sugar (WHO daily advice) and 400 mg of caffeine (FDA guidance for healthy adults).
Change them in Trends, and move the time your day starts in Settings, for example to 4 AM, to fit your life.

■ Trends
See how much you left each day of the week, cup by cup.

■ SugarCap Pro
- Monthly trends and comparison with last week
- Cut-back goal: lowers your daily limit a little at a time over several weeks. Keep to it 5 or more days in a week and next week's limit goes down. Weeks you miss keep the same limit.
- Widget

■ No account, no server
There's nothing to sign up for. Your entries stay on this device and are never sent anywhere.

Purchase information
- SugarCap Pro Yearly: auto-renewing subscription. It renews automatically unless canceled at least 24 hours before the end of the current period. Manage or cancel it in your App Store account settings.
- SugarCap Pro Lifetime: a one-time, non-consumable purchase.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://sugarcap.vercel.app/en/privacy/
```

심사 메모(영어):
```
SugarCap is a local logging app with no account and no server. Every feature works without signing in.
Sugar and caffeine values for cafe drinks are copied from what each brand publishes on its official website or nutrition guide. Values a brand does not publish are shown as "Not published".
In-app purchase is SugarCap Pro only (yearly subscription or lifetime). Logging and closing the day are fully available without it.
The menu follows the device region (United States: Starbucks and Dutch Bros; elsewhere: Korean cafes) and can be changed in Settings > Menu country.
```

앱 개인정보 문항(§6)은 나라와 상관없이 하나라 그대로다. 연령 등급(§7)도 같다.

스크린샷: CI `store-screenshots` 아티팩트의 `en-US/` 폴더(01-today·02-trends·03-feeding·04-paywall). 영어·미국 지역·미국 메뉴로, 데모 기록은 미국 Starbucks 값(`DemoData`)이다.

## 12. 번체 중국어(대만) 현지화 (SPEC §9.9 ④ 초안)

ASC에서 "Chinese (Traditional)" 현지화를 추가하고 아래를 넣는다. 한국어·영어 현지화는 그대로 둔다.
앱은 기기 지역이 대만이면 대만 메뉴(cama café·可不可熟成紅茶, `data/catalog-tw.json` 143종)를 연다.
글자 수는 스크립트로 셌다(부제 14/30, 키워드 54/100, 프로모션 71/170, 설명 872/4,000).

| 항목 | 값 |
|---|---|
| 이름 | SugarCap |
| 부제 | 每一杯的糖和咖啡因，一目了然 |
| 개인정보처리방침 URL | https://sugarcap.vercel.app/zh-Hant/privacy/ (`site/zh-Hant/privacy/index.html`). 앱 페이월 링크도 화면 언어가 번체면 이 주소 |
| 지원 URL | https://sugarcap.vercel.app/ (한국어 페이지. 번체 지원 페이지는 미정) |
| 가격 | 연간 NT$190, 평생 NT$590. 미국 가격의 ASC 자동 환산을 그대로 둔다(2026-10-08 조회). 수동 지정은 대표님 결정 |

키워드:
```
糖,咖啡因,飲料,手搖飲,記錄,減糖,控糖,咖啡,奶茶,拿鐵,紅茶,健康,追蹤,每日,上限,cama,可不可
```
브랜드명은 한국어·영어 키워드와 같은 이유로 심사에서 걸릴 수 있다. 걸리면 빼고 일반 단어로 채운다.

프로모션 텍스트:
```
每天一杯糖和咖啡因，每喝一杯就少一點。晚上把剩下的餵給羅秀和卡因。收錄 cama café 與可不可熟成紅茶 140 多款飲料，點兩下就記好。
```

설명:
```
SugarCap 是幫你減少糖和咖啡因的飲料記錄 App。

■ 喝一杯，杯子就少一點
每天從一杯裝滿每日上限的杯子開始。每記錄一杯飲料，就從杯子裡扣掉那一份。
你看到的是還剩多少，而不只是一個數字。

■ 晚上把剩下的餵掉
結算今天時，羅秀吃掉剩下的糖，卡因吃掉剩下的咖啡因。
喝得越少，牠們吃得越多，也跟你越親近。喝多的日子也不會被責備。

■ 140 多款連鎖飲料
cama café 與可不可熟成紅茶，依杯型分開。
選品牌和飲料，糖和咖啡因就直接記上。
我們只使用品牌公開的數值。品牌沒公開的，就顯示「未公開」，絕不自己編數字。
cama café 公開的是全糖時的最高值；咖啡因只以區間（≤100、101–200、≥201 mg）公開的飲料，會顯示區間，並以區間上限計算。
菜單上沒有的飲料，可以手動輸入。

■ 每日上限由你決定
預設為糖 50 g（WHO 每日建議）與咖啡因 300 mg（台灣食藥署建議）。
在「趨勢」中修改上限，也可以在「設定」把一天的開始時間移到例如凌晨 4 點，配合你的作息。

■ 趨勢
一杯一杯地看這週每天剩下多少。

■ SugarCap Pro
- 每月趨勢，以及與上週比較
- 減量目標：花幾週時間一點一點降低每日上限。一週內守住 5 天以上，下週的上限就會降低；沒守住的週維持原上限。
- 小工具

■ 不用帳號，沒有伺服器
不需要註冊。你的記錄只存在這台裝置上，不會傳送到任何地方。

購買資訊
- SugarCap Pro 年訂閱：自動續訂。除非在目前期間結束前至少 24 小時取消，否則會自動續訂。可在 App Store 帳號設定中管理或取消。
- SugarCap Pro 永久版：一次性購買（非消耗性項目）。

使用條款：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
隱私權政策：https://sugarcap.vercel.app/zh-Hant/privacy/
```

심사 메모는 영어판(§11) 문장에 대만 줄을 더해 바꿔 넣는다:
```
SugarCap is a local logging app with no account and no server. Every feature works without signing in.
Sugar and caffeine values for cafe drinks are copied from what each brand publishes on its official website or nutrition guide. Values a brand does not publish are shown as "Not published".
In Taiwan, chains may publish caffeine as a range (<=100, 101-200, >=201 mg) under the local labeling rule. The app shows the range and counts its upper bound.
In-app purchase is SugarCap Pro only (yearly subscription or lifetime). Logging and closing the day are fully available without it.
The menu follows the device region (United States: Starbucks and Dutch Bros; Taiwan: cama café and KEBUKE; elsewhere: Korean cafes) and can be changed in Settings > Menu country.
```

스크린샷: CI `store-screenshots` 아티팩트의 `zh-Hant/` 폴더(01-today·02-trends·03-feeding·04-paywall). 번체·대만 지역·대만 메뉴로, 데모 기록은 cama café 실값(`DemoData`)이다.
