# 배포 — TestFlight

빌드·서명·업로드는 전부 GitHub Actions macOS 러너에서 돈다(`.github/workflows/testflight.yml`).
로컬 Windows에는 Xcode가 없으므로 **Swift 컴파일 검증도 CI가 유일한 경로**다.

## 워크플로 두 갈래

| 트리거 | 잡 | 하는 일 | 시크릿 |
|---|---|---|---|
| `SugarCap/**` 푸시·PR | `build` | 서명 없이 컴파일만 확인 | 불필요 |
| Actions 탭 수동 실행 | `testflight` | 아카이브 → TestFlight 업로드 | 4개 필요 |

private 리포의 macOS 러너는 **분당 10배로 과금**된다(무료 2,000분 = macOS 실질 200분).
그래서 업로드는 자동 트리거로 걸지 않았다. 한도가 빠듯해지면 리포를 public으로 돌리는 게
가장 싼 해법이다(public 리포는 macOS 러너 무료).

## 한 번만 해야 하는 준비 (대표님 계정 작업)

### 1. Bundle ID 등록
[developer.apple.com > Certificates, Identifiers & Profiles > Identifiers](https://developer.apple.com/account/resources/identifiers/list)
에서 App ID 추가 → Bundle ID `com.sugarcap.app` (Explicit).

### 2. App Store Connect 앱 레코드 생성
[App Store Connect > 앱 > +](https://appstoreconnect.apple.com/apps) →
플랫폼 iOS, 이름 `슈가캡`, 기본 언어 한국어, Bundle ID `com.sugarcap.app`, SKU는 아무 문자열(`sugarcap-ios`).

> 앱 레코드가 없으면 업로드가 거부된다. 심사 제출은 아직 안 한다 — TestFlight 내부 테스터는 심사 없이 바로 쓸 수 있다.

### 3. App Store Connect API 키 발급
App Store Connect > **사용자 및 액세스** > **통합** 탭 > **App Store Connect API** >
**팀 키** > `+` → 역할 **관리자(Admin)** → 생성.

> App Manager(앱 관리) 키는 안 된다. export의 cloud signing이 `Cloud signing permission error`로 거부한다.
> 키 권한은 생성 후 올릴 수 없으니 처음부터 관리자로 만든다.

발급 직후 세 가지를 확보한다:
- **Issuer ID** — 키 목록 상단에 표시되는 UUID
- **Key ID** — 생성된 키 행의 10자리 문자열
- **`AuthKey_<KeyID>.p8`** — **다운로드는 단 한 번만 가능하다.** 잃어버리면 키를 폐기하고 새로 발급해야 한다.

### 4. Team ID 확인
[developer.apple.com > Membership details](https://developer.apple.com/account) 의 Team ID (10자리).

### 5. GitHub Secrets 4개 등록

`.p8`는 그대로 넣을 수 없어 base64로 한 줄로 만든다. Git Bash 기준:

```bash
base64 -w0 ~/Downloads/AuthKey_ABCD123456.p8
```

PowerShell 기준:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_ABCD123456.p8"))
```

리포에 등록(`gh` CLI가 이미 로그인돼 있다):

```bash
gh secret set ASC_KEY_ID    --repo Yewon419/sugarcap --body "ABCD123456"
gh secret set ASC_ISSUER_ID --repo Yewon419/sugarcap --body "69a6de70-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
gh secret set TEAM_ID       --repo Yewon419/sugarcap --body "XXXXXXXXXX"
gh secret set ASC_KEY_P8    --repo Yewon419/sugarcap --body "<위 base64 한 줄>"
```

| Secret | 값 |
|---|---|
| `ASC_KEY_ID` | API 키의 Key ID (10자리) |
| `ASC_ISSUER_ID` | API 키의 Issuer ID (UUID) |
| `ASC_KEY_P8` | `AuthKey_*.p8`를 base64로 인코딩한 한 줄 |
| `TEAM_ID` | Apple Developer Team ID (10자리) |

## 업로드 실행

GitHub > Actions > **iOS** > **Run workflow** (main 브랜치).

끝나면 App Store Connect > 앱 > TestFlight에 빌드가 올라온다.
처리에 5~15분 걸리고, 내부 테스터는 심사 없이 바로 설치할 수 있다.

## 버전·빌드 번호

- `MARKETING_VERSION` (현재 `1.0`) — `SugarCap/project.yml`에서 손으로 올린다.
  App Store Connect의 앱 버전(1.0)보다 낮으면 업로드가 거부된다(2026-09-24에 0.1.0 → 1.0으로 맞춤).
- `CURRENT_PROJECT_VERSION` — CI가 `github.run_number`로 덮어쓴다. 실행할 때마다 자동 증가하므로
  "이 빌드 번호는 이미 사용됨" 오류가 나지 않는다.

## 아직 플레이스홀더인 것

- **앱 아이콘** — `SugarCap/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 는
  업로드 검증을 통과시키려고 코드로 그린 임시 이미지다. 실제 아이콘으로 교체해야 한다.
- **카인 · 로슈 스프라이트** — Phase 1c에서 임시 이미지로 채운다. 최종 원화로 교체 전제.
- **루트 화면** — Phase 1a는 파이프라인 확인용 한 장짜리다. Phase 1c에서 오늘 화면으로 교체한다.
