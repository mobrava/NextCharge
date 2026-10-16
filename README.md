# NextCharge

구독 결제일과 월 고정비를 보여주는 macOS 앱. 외부 의존성 없는 SwiftUI 앱이고, 데이터는 내 맥에만 저장된다.

- 다음 결제일 순으로 정렬, D-day 표시
- 원화 기준 월 고정비, 연 환산, 30일 안에 나갈 금액
- 결제 N일 전과 당일 알림 (무료 체험 종료일 포함)
- 메뉴바에서 바로 확인
- USD 금액은 설정에서 입력한 환율로 환산

데이터 위치: `~/Library/Application Support/NextCharge/subscriptions.json`

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
