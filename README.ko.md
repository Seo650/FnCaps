# FnCaps

[English](README.md) | 한국어 | [日本語](README.ja.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Українська](README.uk.md) | [Русский](README.ru.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md)

FnCaps는 macOS에서 입력 소스 3개 이상을 쓰면서 전환이 느리다고 느끼는 모든 사람을 위한 메뉴 막대 앱입니다.

macOS는 키 하나로 모든 입력 소스를 순서대로 넘깁니다. 3개 이상이면 원하는 언어가 나올 때까지 여러 번 눌러야 하고, 한 번 지나치면 다시 한 바퀴를 돌려야 합니다.

FnCaps는 입력 소스를 Caps Lock과 fn(🌐) 두 키에 나눠 담습니다.

- 키마다 자기 목록이 있고, 그 키는 자기 목록 안에서만 전환합니다.
- 어느 언어를 어느 키에 둘지는 직접 정합니다. 예를 들어 Caps Lock에 영어, fn에 나머지 언어를 둡니다.
- 긴 목록 하나가 짧은 목록 둘이 됩니다. FnCaps 권장 배치에서는 한두 번 누르면 원하는 언어로 가므로 타이핑이 끊기지 않습니다.
- 언어가 더 많으면 입력 소스에 단축키를 지정해 바로 갈 수 있습니다.
- Caps Lock 전환에는 지연이 없습니다. 길게 누르면 원래대로 Caps Lock을 켜고 끕니다.

> **첫 실행:** FnCaps는 Apple 공증을 받지 않아 macOS가 한 번 막습니다. 시스템 설정 > 개인정보 보호 및 보안을 열고 「그래도 열기」를 클릭합니다. 자세한 단계는 [그래도 열기](#open-anyway)에 있습니다.

> FnCaps는 1.0 전까지 초기 개발 단계입니다.

## 요구 사항

- macOS 14 Sonoma 이상, Apple silicon 또는 Intel
- 손쉬운 사용 권한. fn과 Caps Lock 누름을 알아채는 데 필요합니다.

## 설치

### Homebrew

```sh
brew install --cask Seo650/tap/fncaps
```

### GitHub Releases

1. [Releases](https://github.com/Seo650/FnCaps/releases/latest)에서 최신 `FnCaps-x.y.z.zip`을 받습니다.
2. 압축을 풉니다.
3. `FnCaps.app`을 `/Applications`로 옮깁니다.

## 첫 실행

<a id="open-anyway"></a>

### 그래도 열기

FnCaps는 자체 인증서로 서명했고 Apple 공증을 받지 않아, macOS가 첫 실행을 막습니다. 한 번만 일어납니다.

1. FnCaps를 엽니다. macOS가 앱을 확인할 수 없다고 합니다. 「완료」를 클릭합니다.
2. 시스템 설정 > 개인정보 보호 및 보안을 엽니다.
3. 「보안」 아래에서 「그래도 열기」를 클릭합니다.
4. 암호를 입력하거나 Touch ID를 쓴 뒤 「열기」를 클릭합니다.

「그래도 열기」 버튼은 실행이 막힌 뒤에만 나타나고 한 시간쯤 남아 있습니다. 사라졌으면 FnCaps를 다시 엽니다. 명령어가 편하면 아래로 차단을 풉니다.

```sh
xattr -dr com.apple.quarantine /Applications/FnCaps.app
```

### 설정

FnCaps가 열리면 손쉬운 사용 권한과 키 배치를 차례로 안내합니다. 권한은 fn과 Caps Lock 누름을 알아채는 데 필요합니다. 모든 항목은 나중에 FnCaps 설정에서 바꿀 수 있습니다.

## 업데이트

FnCaps는 하루 한 번 새 버전을 확인합니다. 설치하려면 FnCaps 설정에서 「FnCaps 정보」로 가 「업데이트」를 클릭합니다. 클릭하기 전에는 아무것도 설치하지 않습니다. Homebrew로 설치한 경우도 같습니다.

모든 릴리스를 같은 인증서로 서명하므로 업데이트해도 손쉬운 사용 권한이 유지됩니다.

## FnCaps가 보내는 것

FnCaps는 입력한 글자를 기록하지 않습니다. 인터넷에 접속하는 경우는 두 가지입니다.

- 업데이트 확인: 하루 한 번 GitHub API에 최신 릴리스를 묻습니다. 요청에는 앱 버전만 들어가고, 사용자에 관한 다른 정보는 없습니다.
- 문제 알리기: 「보내기」를 클릭하기 전에는 아무것도 보내지 않습니다. 보내는 내용은 메시지, 적었다면 이메일, 앱과 macOS 버전, Mac 모델, 키보드 종류, FnCaps 설정, 입력 소스, 최근 동작 기록, 하루 횟수 제한에만 쓰는 무작위 설치 번호입니다. 입력한 글자, 일련번호와 그 밖의 기기 식별값은 들어가지 않습니다. 보내기 전에 전부 읽을 수 있습니다. 신고는 개발자만 볼 수 있는 비공개 저장소에 저장됩니다.
- 횟수 제한: 설치본 하나에 하루 5번, 같은 네트워크 주소에서 1분에 5번입니다.

## 알려진 한계

- 암호 입력란: macOS가 암호 입력란을 영어로 고정하므로 FnCaps가 언어를 전환하지 않고, Caps Lock을 길게 눌러도 Caps Lock이 켜지지 않습니다.
- Control+Space: FnCaps가 켜져 있는 동안 입력 소스를 전환하지 않습니다. FnCaps를 끄거나 종료하면 다시 동작합니다.
- Caps Lock 표시등: 키를 길게 눌러 Caps Lock을 켜도 키의 표시등은 꺼져 있습니다. 대문자는 정상으로 입력됩니다.
- 언어 표시: 키를 빠르게 누르면 macOS가 커서 옆에 보여 주는 작은 표시가 실제 언어와 다를 수 있습니다. 메뉴 막대 표시는 맞습니다.
- 영어 자판: FnCaps는 ABC와 U.S.를 영어로 봅니다. ABC – AZERTY와 ABC – QWERTZ는 프랑스어와 독일어로 봅니다.
- Karabiner-Elements와 gksdud: 같은 키를 바꾸는 앱입니다. `caps_lock`을 쓰는 Karabiner 규칙은 FnCaps보다 먼저 키를 가져갑니다. 둘 중 하나가 실행 중이면 FnCaps가 경고를 보여 줍니다.
- 시험하지 않았지만 동작할 것으로 보는 것: 외장 키보드를 뽑았다가 다시 연결하기, macOS 14~26, Apple silicon MacBook Air가 아닌 Mac.

## 복구

Caps Lock이 동작하지 않을 때:

- FnCaps 메뉴 막대 아이콘에서 「키 복구」를 고르거나, 설정 > 일반에서 「지금 복구」를 클릭합니다. Caps Lock과 입력 소스 단축키가 FnCaps를 쓰기 전 상태로 돌아갑니다.
- 충돌 등으로 FnCaps가 실행 중이 아니면 Caps Lock이 바뀐 채 남아 아무 동작도 하지 않을 수 있습니다. 터미널에서 아래를 실행한 뒤 FnCaps를 다시 엽니다.

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```

- 이 저장소를 복제했다면 아래 스크립트가 키 변경을 지우고 입력 소스 단축키도 되돌립니다.

  ```sh
  scripts/caps-recover.sh --restore
  ```

FnCaps를 종료한 뒤에도 Control+Space가 입력 소스를 전환하지 않으면 시스템 설정 > 키보드 > 키보드 단축키 > 입력 소스 > 「이전 입력 소스 선택」을 확인합니다. 「키 복구」가 이것을 FnCaps를 쓰기 전 상태로 되돌립니다.

## 삭제

먼저 FnCaps를 종료합니다. 종료하면 Caps Lock과 입력 소스 단축키가 원래대로 돌아갑니다. 그다음 아래를 실행합니다.

```sh
brew uninstall --cask fncaps
```

또는 `/Applications`의 `FnCaps.app`을 휴지통으로 옮깁니다. 설정까지 지우려면 `brew uninstall --zap --cask fncaps`를 씁니다.

## 소스에서 빌드

```sh
swift build
scripts/build-app.sh
```

`scripts/build-app.sh`는 `build/FnCaps.app`을 만듭니다. "FnCaps Dev Local" 인증서가 있으면 그것으로, 없으면 ad-hoc 서명으로 서명합니다. ad-hoc 서명이면 빌드할 때마다 macOS가 손쉬운 사용 권한을 다시 요구합니다. `scripts/make-local-identity.sh`가 로컬 인증서를 만듭니다.

## 기여

이슈와 풀 리퀘스트를 환영합니다. 앱과 이 README는 10개 언어로 번역되어 있습니다. 대부분의 번역은 원어민 검수를 받지 않았으므로 번역 수정을 특히 환영합니다.

## 라이선스

MIT. [LICENSE](LICENSE)를 참고합니다.
