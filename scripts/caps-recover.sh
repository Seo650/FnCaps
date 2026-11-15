#!/usr/bin/env bash
# FnCaps가 바꾸는 시스템 값(단축키 #60, UserKeyMapping)을 기준값으로 되돌리는 복구 명령.
#   --snapshot  읽기 전용. 현재 #60을 ~/Library/Application Support/FnCaps/caps-baseline-60.plist 에 저장한다.
#               이미 파일이 있고 현재 #60이 FnCaps 값이면 덮어쓰지 않는다.
#               파일이 없는데 현재 #60이 FnCaps 값이면 거부한다(F18을 기준값으로 저장하지 않는다).
#               새 위치에 파일이 없고 옛 위치(~/fncaps-spike)에 있으면 옛 파일을 복사해 쓴다(옛 파일은 지우지 않는다).
#   --restore   앱을 끄고, Caps 매핑을 비우고, #60을 되돌린 뒤 반영한다.
#               매핑: Caps 외 항목이 있으면 지우지 않고 알린 뒤 실패로 끝낸다(#60도 건드리지 않는다).
#               #60: 앱을 끈 뒤 앱 값(65535...)일 때만 덮어쓴다. 원래 값은 기준값 파일, 없으면 앱 설정의 originalShortcut.
#   --selftest  임시 파일과 문자열로 분기 규칙만 시험한다(defaults, hidutil에 닿지 않음).
# 단계가 실패해도 끝까지 가서 실패 목록과 현재 값을 보여 준다.
set -u

PB=/usr/libexec/PlistBuddy
ACTIVATE=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
ROOT="$HOME/Library/Application Support/FnCaps"
BASELINE="$ROOT/caps-baseline-60.plist"
LEGACY_BASELINE="$HOME/fncaps-spike/caps-baseline-60.plist"
APP_DOMAIN="io.github.seo650.fncaps"
CAPS_DEC=30064771129  # 0x700000039
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 기준값 파일이 「항목 없음」 표시인가.
baseline_absent() { "$PB" -c "Print :fncaps-absent" "$1" >/dev/null 2>&1; }

# 전체 plist 파일에서 #60 첫 번째 인자(65535면 FnCaps 값).
first_param() { "$PB" -c "Print :AppleSymbolicHotKeys:60:value:parameters:0" "$1" 2>/dev/null; }

# merge_60 BASELINE CURRENT OUT : CURRENT에서 60번 항목만 기준값으로 교체한다. 다른 항목은 그대로 둔다.
merge_60() {
  local base="$1" cur="$2" out="$3"
  cp "$cur" "$out" || return 1
  "$PB" -c "Delete :AppleSymbolicHotKeys:60" "$out" >/dev/null 2>&1 || true
  if baseline_absent "$base"; then
    return 0
  fi
  "$PB" -c "Add :AppleSymbolicHotKeys:60 dict" "$out" >/dev/null || return 1
  "$PB" -c "Merge $base :AppleSymbolicHotKeys:60" "$out" >/dev/null || return 1
}

# hidutil UserKeyMapping 출력 문자열에서 Caps(0x700000039) 외 항목 수.
non_caps_count() {
  local line v n=0
  while IFS= read -r line; do
    v="${line##*= }"
    v="${v%;}"
    case "$v" in 0x* | 0X*) v=$((v)) ;; esac
    [ "$v" = "$CAPS_DEC" ] || n=$((n + 1))
  done < <(printf '%s\n' "$1" | grep 'HIDKeyboardModifierMappingSrc')
  echo "$n"
}

# 앱 설정에 남은 원래 #60을 OUT(xml plist)에 꺼낸다. 앱을 끄기 전에 불러야 한다(정상 종료가 지운다).
# 반환: 0 항목 저장, 3 백업은 있으나 원래 항목 없음, 1 백업 없음.
# 둘째 인자(시험용)가 있으면 defaults를 읽지 않고 그 plist를 앱 설정으로 쓴다.
capture_app_original() {
  local out="$1" dom="$WORK/app-domain.plist" b64
  if [ -n "${2:-}" ]; then
    dom="$2"
  else
    defaults export "$APP_DOMAIN" "$dom" >/dev/null 2>&1 || return 1
  fi
  [ "$("$PB" -c "Print :shortcutBackedUp" "$dom" 2>/dev/null)" = "true" ] || return 1
  b64="$(plutil -extract originalShortcut raw -o - "$dom" 2>/dev/null)" || return 3
  [ -n "$b64" ] || return 3
  printf '%s' "$b64" | base64 -D >"$WORK/app-orig.bin" 2>/dev/null || return 1
  plutil -convert xml1 -o "$out" "$WORK/app-orig.bin" 2>/dev/null || return 1
  return 0
}

# decide_60 현재첫인자 기준값파일있음(1/0) 앱백업상태(0/3/1) : leave | baseline | app | none
decide_60() {
  if [ "$1" != "65535" ]; then
    echo leave
  elif [ "$2" = 1 ]; then
    echo baseline
  elif [ "$3" = 0 ] || [ "$3" = 3 ]; then
    echo app
  else
    echo none
  fi
}

show_current() {
  echo "현재 #60:"
  defaults export com.apple.symbolichotkeys "$WORK/now.plist" >/dev/null 2>&1 \
    && "$PB" -c "Print :AppleSymbolicHotKeys:60" "$WORK/now.plist" 2>&1 | sed 's/^/  /'
  echo "현재 UserKeyMapping:"
  hidutil property --get UserKeyMapping 2>&1 | sed 's/^/  /'
}

snapshot() {
  mkdir -p "$ROOT" || { echo "폴더를 만들 수 없습니다: $ROOT" >&2; return 1; }
  # 옛 위치에만 기준값이 있으면 새 위치로 복사해 쓴다(옛 파일은 그대로 둔다).
  if [ ! -f "$BASELINE" ] && [ -f "$LEGACY_BASELINE" ]; then
    if cp "$LEGACY_BASELINE" "$BASELINE"; then
      echo "옛 기준값 파일을 그대로 씁니다: $LEGACY_BASELINE -> $BASELINE"
    else
      echo "옛 기준값 파일을 복사할 수 없습니다: $LEGACY_BASELINE" >&2
      return 1
    fi
  fi
  defaults export com.apple.symbolichotkeys "$WORK/now.plist" >/dev/null 2>&1 \
    || { echo "defaults export 실패" >&2; return 1; }
  local first
  first="$(first_param "$WORK/now.plist")"
  if [ -f "$BASELINE" ]; then
    if [ "$first" = "65535" ]; then
      echo "기준값 파일이 이미 있고 현재 #60이 FnCaps 값이라 덮어쓰지 않습니다: $BASELINE"
      return 0
    fi
  elif [ "$first" = "65535" ]; then
    echo "거부: 기준값 파일이 없는데 현재 #60이 이미 FnCaps 값(65535...)입니다. 기준값으로 저장하지 않습니다." >&2
    return 3
  fi
  if plutil -extract AppleSymbolicHotKeys.60 xml1 -o "$WORK/entry.plist" "$WORK/now.plist" 2>/dev/null; then
    cp "$WORK/entry.plist" "$BASELINE" || return 1
    echo "기준값 저장: $BASELINE"
    "$PB" -c "Print :value:parameters" -c "Print :enabled" "$BASELINE" 2>&1 | tr '\n' ' '; echo
  else
    plutil -create xml1 "$BASELINE" && "$PB" -c "Add :fncaps-absent bool true" "$BASELINE" >/dev/null || return 1
    echo "기준값 저장(원래 #60 항목 없음): $BASELINE"
  fi
}

restore() {
  local failed=() app_state=1 have_base=0 mapping_ok=1 base_file="$BASELINE"
  if [ -f "$BASELINE" ]; then
    have_base=1
  elif [ -f "$LEGACY_BASELINE" ]; then
    # 새 위치로 옮기기 전에 만든 기준값은 옛 위치에서 읽는다(옛 파일은 지우지 않는다).
    have_base=1
    base_file="$LEGACY_BASELINE"
  fi
  # 0. 앱 설정의 원래 #60을 먼저 챙긴다(정상 종료가 앱 설정을 지운다).
  capture_app_original "$WORK/app-orig.plist"
  app_state=$?
  # 1. 앱 종료(앱이 스스로 복원할 시간을 준다). 떠 있지 않으면 osascript가 앱을 띄우지 않게 건너뛴다.
  if pgrep -x FnCaps >/dev/null 2>&1; then
    osascript -e 'with timeout of 2 seconds' -e 'tell application "FnCaps" to quit' -e 'end timeout' >/dev/null 2>&1 || true
    local i
    for i in $(seq 1 30); do
      pgrep -x FnCaps >/dev/null 2>&1 || break
      sleep 0.1
    done
    if pgrep -x FnCaps >/dev/null 2>&1; then
      pkill -9 -x FnCaps || failed+=("앱 강제 종료")
      sleep 0.3
    fi
  fi
  # 2. 매핑 먼저. 기준값 파일과 무관하다. Caps 외 항목이 있으면 지우지 않는다.
  local cur_map others
  if cur_map="$(hidutil property --get UserKeyMapping 2>&1)"; then
    others="$(non_caps_count "$cur_map")"
    if [ "$others" -gt 0 ]; then
      mapping_ok=0
      failed+=("UserKeyMapping에 Caps 외 항목 ${others}개가 있어 지우지 않음")
      echo "Caps 외 매핑이 있어 지우지 않습니다. 직접 정리한 뒤 다시 실행하세요: hidutil property --get UserKeyMapping" >&2
    else
      hidutil property --set '{"UserKeyMapping":[]}' >/dev/null 2>&1 || { mapping_ok=0; failed+=("UserKeyMapping 비우기"); }
    fi
  else
    mapping_ok=0
    failed+=("UserKeyMapping 읽기")
  fi
  # 3. #60: 앱 값일 때만 덮어쓴다. 매핑이 그대로면 키가 F 키를 내는 중이므로 건드리지 않는다.
  if [ "$mapping_ok" = 1 ]; then
    if defaults export com.apple.symbolichotkeys "$WORK/cur.plist" >/dev/null 2>&1; then
      local act
      act="$(decide_60 "$(first_param "$WORK/cur.plist")" "$have_base" "$app_state")"
      local src=""
      case "$act" in
        leave) echo "#60은 이미 앱 값이 아니라 그대로 둡니다." ;;
        baseline) src="$base_file" ;;
        app)
          if [ "$app_state" = 0 ]; then
            src="$WORK/app-orig.plist"
          else
            plutil -create xml1 "$WORK/app-absent.plist" && "$PB" -c "Add :fncaps-absent bool true" "$WORK/app-absent.plist" >/dev/null
            src="$WORK/app-absent.plist"
          fi
          ;;
        none)
          failed+=("#60 원래 값을 알 수 없음(기준값 파일도 앱 백업도 없음)")
          echo "#60이 앱 값이지만 원래 값을 알 수 없어 건드리지 않습니다." >&2
          ;;
      esac
      if [ -n "$src" ]; then
        if merge_60 "$src" "$WORK/cur.plist" "$WORK/out.plist" \
          && defaults import com.apple.symbolichotkeys "$WORK/out.plist" >/dev/null 2>&1; then
          :
        else
          failed+=("#60 복원")
        fi
      fi
    else
      failed+=("#60 읽기")
    fi
  else
    echo "매핑이 남아 있어 #60은 건드리지 않습니다." >&2
  fi
  # 4. 반영.
  if [ -x "$ACTIVATE" ]; then
    "$ACTIVATE" -u -virtualSession >/dev/null 2>&1 || failed+=("activateSettings")
  else
    failed+=("activateSettings 없음")
  fi
  if [ "${#failed[@]}" -eq 0 ]; then
    echo "복구 완료"
  else
    echo "실패한 단계: ${failed[*]}" >&2
  fi
  show_current
  [ "${#failed[@]}" -eq 0 ]
}

selftest() {
  local d="$WORK/selftest" ok=1 n
  mkdir -p "$d"
  # 현재 값: 60 = FnCaps 값, 32 와 10 은 다른 사용자 값.
  plutil -create xml1 "$d/cur.plist"
  "$PB" -c "Add :AppleSymbolicHotKeys dict" "$d/cur.plist"
  for n in 60 32 10; do
    "$PB" -c "Add :AppleSymbolicHotKeys:$n dict" -c "Add :AppleSymbolicHotKeys:$n:enabled bool true" "$d/cur.plist"
  done
  "$PB" -c "Add :AppleSymbolicHotKeys:60:value dict" -c "Add :AppleSymbolicHotKeys:60:value:parameters array" \
    -c "Add :AppleSymbolicHotKeys:60:value:parameters: integer 65535" "$d/cur.plist"
  # 기준값: 비활성 항목.
  plutil -create xml1 "$d/base.plist"
  "$PB" -c "Add :enabled bool false" -c "Add :value dict" -c "Add :value:parameters array" \
    -c "Add :value:parameters: integer 32" "$d/base.plist"
  merge_60 "$d/base.plist" "$d/cur.plist" "$d/out.plist" || ok=0
  [ "$("$PB" -c "Print :AppleSymbolicHotKeys:60:enabled" "$d/out.plist" 2>/dev/null)" = "false" ] || { echo "FAIL 60 교체" >&2; ok=0; }
  [ "$("$PB" -c "Print :AppleSymbolicHotKeys:60:value:parameters:0" "$d/out.plist" 2>/dev/null)" = "32" ] || { echo "FAIL 60 값" >&2; ok=0; }
  [ "$("$PB" -c "Print :AppleSymbolicHotKeys:32:enabled" "$d/out.plist" 2>/dev/null)" = "true" ] || { echo "FAIL 32 유지" >&2; ok=0; }
  [ "$("$PB" -c "Print :AppleSymbolicHotKeys:10:enabled" "$d/out.plist" 2>/dev/null)" = "true" ] || { echo "FAIL 10 유지" >&2; ok=0; }
  # 원래 항목이 없었던 경우: 60번이 지워지고 나머지는 그대로.
  plutil -create xml1 "$d/absent.plist"
  "$PB" -c "Add :fncaps-absent bool true" "$d/absent.plist"
  baseline_absent "$d/absent.plist" || { echo "FAIL absent 판별" >&2; ok=0; }
  baseline_absent "$d/base.plist" && { echo "FAIL present 판별" >&2; ok=0; }
  merge_60 "$d/absent.plist" "$d/cur.plist" "$d/out2.plist" || ok=0
  "$PB" -c "Print :AppleSymbolicHotKeys:60" "$d/out2.plist" >/dev/null 2>&1 && { echo "FAIL 60 삭제" >&2; ok=0; }
  [ "$("$PB" -c "Print :AppleSymbolicHotKeys:32:enabled" "$d/out2.plist" 2>/dev/null)" = "true" ] || { echo "FAIL 32 유지(없음)" >&2; ok=0; }
  # WR-07: Caps 외 매핑 수 (실제 hidutil에 닿지 않는다).
  local none_out empty_out caps_only mixed
  none_out="(null)"
  empty_out="("$'\n'")"
  caps_only="("$'\n'"    {"$'\n'"        HIDKeyboardModifierMappingDst = 30064771181;"$'\n'"        HIDKeyboardModifierMappingSrc = 30064771129;"$'\n'"    }"$'\n'")"
  mixed="$caps_only"$'\n'"        HIDKeyboardModifierMappingSrc = 30064771172;"
  [ "$(non_caps_count "$none_out")" = 0 ] || { echo "FAIL 매핑 없음" >&2; ok=0; }
  [ "$(non_caps_count "$empty_out")" = 0 ] || { echo "FAIL 빈 매핑" >&2; ok=0; }
  [ "$(non_caps_count "$caps_only")" = 0 ] || { echo "FAIL Caps만" >&2; ok=0; }
  [ "$(non_caps_count "$mixed")" = 1 ] || { echo "FAIL Caps 외 항목" >&2; ok=0; }
  [ "$(non_caps_count "HIDKeyboardModifierMappingSrc = 0x700000039;")" = 0 ] || { echo "FAIL 16진 Caps" >&2; ok=0; }
  # WR-08, WR-09: #60 분기 (현재 첫 인자, 기준값 파일 유무, 앱 백업 상태).
  [ "$(decide_60 32 1 0)" = leave ] || { echo "FAIL 앱 값 아님 -> 그대로" >&2; ok=0; }
  [ "$(decide_60 "" 1 0)" = leave ] || { echo "FAIL #60 없음 -> 그대로" >&2; ok=0; }
  [ "$(decide_60 65535 1 0)" = baseline ] || { echo "FAIL 기준값 우선" >&2; ok=0; }
  [ "$(decide_60 65535 0 0)" = app ] || { echo "FAIL 앱 백업 사용" >&2; ok=0; }
  [ "$(decide_60 65535 0 3)" = app ] || { echo "FAIL 앱 백업(항목 없음)" >&2; ok=0; }
  [ "$(decide_60 65535 0 1)" = none ] || { echo "FAIL 둘 다 없음 -> 실패" >&2; ok=0; }
  # WR-09: 앱 설정의 originalShortcut 추출.
  local b64
  plutil -create xml1 "$d/entry.plist"
  "$PB" -c "Add :enabled bool false" -c "Add :value dict" -c "Add :value:parameters array" \
    -c "Add :value:parameters: integer 32" "$d/entry.plist"
  plutil -convert binary1 -o "$d/entry.bin" "$d/entry.plist"
  b64="$(base64 <"$d/entry.bin" | tr -d '\n')"
  plutil -create xml1 "$d/domain.plist"
  "$PB" -c "Add :shortcutBackedUp bool true" -c "Add :originalShortcut data x" "$d/domain.plist"
  # PlistBuddy로 data를 직접 못 넣으므로 plutil -insert로 base64 데이터를 넣는다.
  plutil -replace originalShortcut -data "$b64" "$d/domain.plist" || ok=0
  capture_app_original "$d/back.plist" "$d/domain.plist"
  [ "$?" = 0 ] || { echo "FAIL 앱 원래 값 상태" >&2; ok=0; }
  [ "$("$PB" -c "Print :value:parameters:0" "$d/back.plist" 2>/dev/null)" = "32" ] || { echo "FAIL 앱 원래 값 추출" >&2; ok=0; }
  # 백업은 있으나 원래 항목이 없으면 3, 백업 표시가 없으면 1.
  plutil -remove originalShortcut "$d/domain.plist"
  capture_app_original "$d/none.plist" "$d/domain.plist"
  [ "$?" = 3 ] || { echo "FAIL 항목 없음 상태" >&2; ok=0; }
  plutil -create xml1 "$d/empty.plist"
  capture_app_original "$d/none.plist" "$d/empty.plist"
  [ "$?" = 1 ] || { echo "FAIL 백업 없음 상태" >&2; ok=0; }
  [ "$ok" = 1 ] || return 1
  echo "SELFTEST OK"
}

case "${1:-}" in
  --snapshot) snapshot ;;
  --restore) restore ;;
  --selftest) selftest ;;
  *) sed -n '2,10p' "$0"; exit 2 ;;
esac
