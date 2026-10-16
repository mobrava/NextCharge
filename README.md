# NextCharge

A small macOS app that shows when each subscription charges next and what they cost per month. SwiftUI only, no dependencies, no account, no network except fetching site logos. Your data stays in one JSON file on your Mac.

English and Korean (follows your macOS language).

- Sorted by next charge, with a countdown
- Monthly total, yearly total, and what's due in the next 30 days, per group or overall
- Groups (folders) with their own monthly totals; drag a subscription onto a group to move it
- Reminders N days before and on the day, including free-trial end dates; per-subscription override
- Menu bar summary
- KRW or USD as the base currency, with a manual exchange rate
- Site logos from the manage-page URL (or a custom logo domain)

Requires macOS 14 or later.

## Install

Download the DMG from Releases, open it, and drag NextCharge to Applications. Builds are signed with Developer ID and notarized.

## Data

`~/Library/Application Support/NextCharge/subscriptions.json`

The app checks this file every 1.5 seconds, so edits made outside the app (by hand, a script, or an AI agent) show up right away. Invalid JSON is ignored and the current list is kept.

```jsonc
{
  "id": "UUID",
  "name": "Typecast API Lite",
  "price": 15,
  "currency": "USD",            // KRW | USD
  "cycle": "monthly",           // weekly | monthly | quarterly | yearly
  "billingAnchor": "2026-10-15T15:00:00Z", // any billing date; today or earlier counts as already paid
  "status": "active",           // active | trial | cancelled
  "endDate": null,              // trial: trial end, cancelled: access end
  "paymentMethod": "Card 1379",
  "manageURL": "https://typecast.ai/developers/api/billing",
  "iconDomain": null,           // fetch the logo from another domain
  "group": "fconlab",           // null = no group
  "remindDays": null,           // null = app default, 0 = day of only, -1 = off, N = N days before
  "notes": ""
}
```

## Build

Only the Xcode Command Line Tools are needed.

```sh
scripts/build-release.sh   # ad-hoc signed, build/NextCharge-<version>.dmg
```

Developer ID signing and notarization:

```sh
SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=<notarytool profile> VERSION=1.3.0 scripts/build-release.sh
```

Translations live in `Resources/<lang>.lproj/Localizable.strings`. Keys are the English strings.

## 한국어

구독 결제일과 월 고정비를 보여주는 macOS 앱이에요. 맥 언어가 한국어면 한국어로 나와요. 그룹별 합계, 결제 전 알림, 메뉴바 요약을 지원하고 데이터는 내 맥의 JSON 파일 하나에만 저장돼요.

## License

MIT
