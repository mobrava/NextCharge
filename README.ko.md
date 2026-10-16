<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="NextCharge 아이콘">
</p>

<h1 align="center">NextCharge</h1>

<p align="center">
  구독마다 다음 결제일과 월 고정비를 보여주는 macOS 앱
</p>

<p align="center">
  <a href="README.md">English</a> | 한국어
</p>

<p align="center">
  <a href="https://github.com/mobrava/NextCharge/releases/latest"><img src="https://img.shields.io/github/v/release/mobrava/NextCharge?style=flat-square" alt="최신 릴리스"></a>
  <a href="https://github.com/mobrava/NextCharge/releases"><img src="https://img.shields.io/github/downloads/mobrava/NextCharge/total?style=flat-square" alt="다운로드 수"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/mobrava/NextCharge?style=flat-square" alt="라이선스"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square" alt="macOS 14 이상">
</p>

<p align="center">
  <a href="https://github.com/mobrava/NextCharge/releases/latest"><strong>DMG 다운로드</strong></a>
</p>

<p align="center">
  <img src="docs/screenshot-main.png" width="900" alt="결제일 순으로 정렬된 NextCharge 메인 창">
</p>

NextCharge는 구독을 결제일이 가까운 순서로 보여주고, 각각 며칠 남았는지와 월 고정비를 위에 띄워줘요. 그룹으로 묶으면 그룹마다 합계가 따로 나와요. 결제 며칠 전과 당일에 알림을 보내고, 무료 체험이 유료로 바뀌기 전에도 알려줘요.

무료 오픈소스이고 macOS 14 Sonoma 이상에서 돌아가요. 계정, 서버, 분석 도구가 없어요.

## 설치

[Releases](https://github.com/mobrava/NextCharge/releases/latest)에서 최신 `.dmg`를 받아 열고, NextCharge를 응용 프로그램 폴더로 끌어다 놓으면 돼요. Apple Developer ID로 서명하고 Apple 공증을 받아서 보안 경고 없이 열려요.

## 사용법

1. <kbd>⌘</kbd> <kbd>N</kbd> 또는 **+** 버튼으로 구독을 추가해요.
2. 금액, 결제 주기, 결제일을 넣어요. 결제일은 다음 결제일이어도 되고 이미 결제한 날이어도 돼요. 그 뒤 날짜는 알아서 계산해요.
3. **관리 페이지**에 계정이나 결제 페이지 주소를 넣으면 이름 옆에 사이트 로고가 뜨고, 우클릭으로 그 페이지를 열 수 있어요.
4. 처음 실행할 때 알림을 허용해요. **설정**의 **테스트 알림**으로 잘 오는지 확인할 수 있어요.

무료 체험은 상태를 **무료 체험**으로 두고 종료일을 넣어요. 해지한 구독은 **해지함**으로 바꾸고 이용 종료일을 넣으면 목록 아래로 내려가고 합계에서 빠져요.

메인 창에서는

- 구독을 더블클릭하면 수정할 수 있어요
- 우클릭으로 관리 페이지 열기, 그룹 이동, 해지 표시, 삭제를 할 수 있어요
- 구독을 사이드바 그룹으로 끌어다 놓으면 옮겨져요. 여러 개를 선택해서 한 번에 옮길 수도 있어요
- <kbd>Delete</kbd>로 선택한 구독을 지워요
- 사이드바 아래 **새 그룹**으로 폴더를 만들어요. 그룹을 우클릭하면 이름을 바꾸거나 지울 수 있고, 그룹을 지워도 안의 구독은 남아요

메뉴바 아이콘을 누르면 월 고정비와 가까운 결제 몇 개가 보여요.

## 기능

- 결제일 순 정렬과 D-day 표시. 일주일 안이면 주황, 3일 안이면 빨강
- 월 고정비, 연 환산, 30일 안에 나갈 금액을 전체 또는 그룹별로
- 그룹(폴더)과 그룹별 월 합계
- 매주, 매월, 3개월, 매년 주기
- 결제 N일 전과 당일, 원하는 시각에 알림. 구독마다 기본값, 당일만, 직접 정한 일수, 끔 중에서 고를 수 있어요
- 무료 체험과 해지한 구독, 각각의 종료일
- 기준 통화 KRW 또는 USD, 환율은 직접 입력
- 관리 페이지나 직접 넣은 도메인에서 사이트 로고 가져오기
- 메뉴바 요약, 로그인 시 실행
- 영어와 한국어, macOS 언어를 따라가요
- 모든 데이터가 JSON 파일 하나에 있어서, 앱이 켜진 상태에서 직접이나 스크립트, AI 에이전트로 고쳐도 바로 반영돼요

## 개인정보

구독 정보는 내 맥의 JSON 파일 하나에만 저장되고 밖으로 나가지 않아요. 계정, 동기화, 분석 도구가 없어요.

네트워크는 관리 페이지에 넣은 사이트의 로고를 가져올 때만 써요. 그 사이트의 첫 페이지와 아이콘을 요청하고, 아이콘이 없으면 Google 파비콘 서비스를 써요. 받은 로고는 데이터 옆에 저장해서 한 번만 받아요. 관리 페이지를 비워두면 아무것도 받지 않아요.

## 자주 묻는 질문

### 앱을 꺼두면 알림이 안 오나요?

와요. 구독마다 앞으로 세 번의 결제 알림을 macOS에 예약해두기 때문에 앱이 꺼져 있어도 와요. 앱을 켜거나 구독을 고칠 때마다 다시 예약해요. 가끔 앱을 열거나 **로그인 시 실행**을 켜두면 계속 앞서서 예약돼요.

### 데이터는 어디 있고, 직접 고쳐도 되나요?

`~/Library/Application Support/NextCharge/subscriptions.json`에 있어요. 앱이 1.5초마다 파일을 확인해서 밖에서 고친 내용도 바로 반영해요. 형식이 잘못된 JSON이면 기존 목록을 그대로 둬요. 필드 설명은 [영어 README](README.md#where-is-my-data-and-can-i-edit-it-directly)에 있어요.

모두 지우려면 앱을 끄고 `NextCharge` 폴더를 지우면 돼요. 앱까지 지우려면 휴지통으로 옮기면 돼요.

### 로고가 엉뚱하게 나와요

로고는 관리 페이지 도메인에서 가져와요. 결제대행사나 다른 도메인의 페이지라면 **로고 도메인**에 브랜드 도메인(예: `slack.com`)을 넣어주세요.

### KRW, USD 말고 다른 통화도 되나요?

아직은 안 돼요. 합계는 KRW나 USD로 보여주고, 둘 사이 환율은 설정에서 직접 넣어요.

### iCloud 동기화나 iPhone 앱이 있나요?

없어요. 맥 앱 하나가 로컬 파일에 모든 걸 저장해요.

## 소스에서 빌드하기

macOS 14 이상과 Xcode Command Line Tools만 있으면 돼요. Xcode 프로젝트도, 외부 의존성도 없어요. 명령어는 [영어 README](README.md#build-from-source)를 참고해주세요.

## 만든 이유

사이드 프로젝트를 준비하다가 하루에 유료 서비스 네 개를 가입했고, 뭐가 언제 결제되는지 놓쳤어요. 구독 관리 앱은 이미 많지만, 데이터를 내가 읽고 고칠 수 있는 파일에 두고 AI 에이전트한테 "이거 추가해줘", "이거 해지했어"라고 맡길 수 있는 앱을 원했어요.

## 라이선스

[MIT License](LICENSE)
