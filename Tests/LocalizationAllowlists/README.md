# 번역 허용 목록

`Tests/FnCapsCoreTests/LocalizationParityTests.swift`의 `untranslatedValuesAbsent` 시험이 읽는 파일이다.
SPM 대상 폴더 밖에 있어 빌드에 들어가지 않는다.

## 파일 이름

`same-as-english-<lang>.txt` — 언어(lproj 이름)마다 하나. 예: `same-as-english-fr.txt`, `same-as-english-zh-Hant.txt`.
파일이 없으면 그 언어의 허용 목록은 빈 목록으로 본다.

## 형식

```
# 주석은 #으로 시작한다.
<key> = <이유>
```

- `<key>`는 `en.lproj/Localizable.strings`에 있는 키여야 한다.
- `<이유>`가 비면 시험이 실패한다.
- 허용한 키의 값이 실제로 영어 값과 다르면(번역을 나중에 넣은 경우) 시험이 실패한다. 낡은 줄은 지운다.

## 허용 이유는 세 가지뿐이다

| 이유 | 뜻 | 예 |
|------|-----|-----|
| `brand` | 고유명사·제품명 | `FnCaps`, `GitHub` |
| `symbol` | 기호·숫자 형식 | `%d ms`, `fn (🌐)` |
| `cognate: <근거>` | 그 언어에서 철자가 영어와 똑같은 맞는 낱말. 콜론 뒤에 그 언어에서 맞는 표기인 근거를 적는다 | `Version = cognate: 독일어에서도 Version이 표준 표기` |

## 자동 허용

`ko`와 `ja` 값이 둘 다 영어 값과 같은 키는 언어 중립(브랜드·기호·`%d ms` 등)으로 보고 허용 목록 없이 통과한다.
번역 계획(04.1-05~07)은 자기 언어 파일만 만들고 고친다. 이 README와 시험 파일은 04.1-03이 정한다.
