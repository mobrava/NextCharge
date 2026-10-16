# NextCharge

구독 결제일과 월 고정비를 보여주는 macOS 앱. 외부 의존성 없는 SwiftUI 앱이고, 데이터는 내 맥에만 저장된다.

- 다음 결제일 순으로 정렬, D-day 표시
- 원화 기준 월 고정비, 연 환산, 30일 안에 나갈 금액
- 결제 N일 전과 당일 알림 (무료 체험 종료일 포함)
- 메뉴바에서 바로 확인
- 그룹(폴더)으로 묶고 그룹별 월 합계 보기. 사이드바로 끌어다 놓아 이동
- 구독마다 알림 일수 따로 지정 (기본값 / 당일만 / N일 전 / 끔)
- USD 금액은 설정에서 입력한 환율로 환산
- 관리 페이지 URL(또는 로고 도메인)로 사이트 로고 자동 표시

데이터 위치: `~/Library/Application Support/NextCharge/subscriptions.json`

앱이 이 파일을 1.5초마다 확인해서, 밖에서 고쳐도 화면과 알림에 바로 반영한다. 잘못된 JSON이면 무시하고 기존 목록을 유지한다.

```json
{
  "id": "UUID",
  "name": "Typecast API Lite",
  "price": 15,
  "currency": "USD",            // KRW | USD
  "cycle": "monthly",           // weekly | monthly | quarterly | yearly
  "billingAnchor": "2026-10-15T15:00:00Z", // 결제일 아무거나 하나. 오늘 이전이면 이미 낸 것으로 보고 다음 주기 계산
  "status": "active",           // active | trial | cancelled
  "endDate": null,              // trial: 체험 종료일, cancelled: 이용 종료일
  "paymentMethod": "카드 1379",
  "manageURL": "https://typecast.ai/developers/api/billing",
  "iconDomain": null,           // 로고를 다른 도메인에서 가져올 때
  "group": "fconlab",           // 그룹 이름, 없으면 null
  "remindDays": null,           // null = 기본값, 0 = 당일만, -1 = 끔, N = N일 전
  "notes": ""
}
```

## 빌드

Xcode Command Line Tools만 있으면 된다. macOS 14 이상.

```sh
scripts/build-release.sh   # ad-hoc 서명, build/NextCharge-1.0.0.dmg
```

Developer ID 서명과 노타리:

```sh
SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=<notarytool profile> scripts/build-release.sh
```

## License

MIT
