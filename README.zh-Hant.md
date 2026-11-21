# FnCaps

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-Hans.md) | 繁體中文 | [Українська](README.uk.md) | [Русский](README.ru.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md)

FnCaps 是 macOS 的選單列應用程式，適合使用三種以上輸入方式、覺得切換很慢的人。

macOS 只提供一個按鍵，依序切換所有輸入方式。使用三種以上時，你得反覆按到想要的語言出現；只要按過頭，就得再繞一整圈。

FnCaps 把輸入方式分成兩個按鍵：Caps Lock 和 fn（🌐）。

- 每個按鍵有自己的清單，只在該清單內切換。
- 由你決定哪個語言放在哪個按鍵。例如，Caps Lock 放英文，fn 放其他語言。
- 一份長清單變成兩份短清單。使用 FnCaps 建議的配置時，想要的語言只差一兩次按鍵，打字不會中斷。
- 語言更多時，可以給某個輸入方式專屬的快速鍵，直接切換過去。
- Caps Lock 切換沒有延遲。按住它則照常開啟或關閉 Caps Lock。

> **首次啟動：** macOS 會阻擋 FnCaps 一次，因為它未經 Apple 公證。打開系統設定 > 隱私權與安全性，然後按「仍要打開」。步驟見[仍要打開](#open-anyway)。

> FnCaps 在 1.0 之前仍在早期開發階段。

## 系統需求

- macOS 14 Sonoma 或後續版本，Apple silicon 或 Intel
- 輔助使用權限。FnCaps 需要此權限才能偵測 fn 和 Caps Lock 的按下動作。

## 安裝

### Homebrew

```sh
brew install --cask Seo650/tap/fncaps
```

### GitHub Releases

1. 從 [Releases](https://github.com/Seo650/FnCaps/releases/latest) 下載最新的 `FnCaps-x.y.z.dmg`。
2. 打開。
3. 將 `FnCaps.app` 拖到 `Applications` 資料夾。

## 首次啟動

<a id="open-anyway"></a>

### 仍要打開

FnCaps 以自有憑證簽署，未經 Apple 公證，因此 macOS 會阻擋第一次啟動。這只會發生一次。

1. 打開 FnCaps。macOS 表示無法驗證此應用程式。按「完成」。
2. 打開系統設定 > 隱私權與安全性。
3. 在「安全性」下方，按「仍要打開」。
4. 輸入密碼或使用 Touch ID，然後按「打開」。

「仍要打開」按鈕只在啟動被阻擋後出現，並保留約一小時。如果按鈕已消失，請再次打開 FnCaps。若偏好命令列，下列指令可解除阻擋：

```sh
xattr -dr com.apple.quarantine /Applications/FnCaps.app
```

### 設定

FnCaps 開啟後，會引導你完成輔助使用權限與按鍵配置。FnCaps 需要此權限才能偵測 fn 和 Caps Lock 的按下動作。之後可以在 FnCaps 設定中變更所有項目。

## 更新

FnCaps 每天檢查一次新版本。如要安裝，打開 FnCaps 設定，前往「關於FnCaps」並按「更新」。在你按下「更新」之前，不會安裝任何內容。Homebrew 使用者也用相同方式更新。

更新會保留輔助使用權限，因為每個版本都以相同憑證簽署。

## FnCaps 傳送的資料

FnCaps 不會記錄你輸入的內容。它只在兩種情況下連上網際網路。

- 更新檢查：FnCaps 每天向 GitHub API 查詢最新版本一次。請求只包含應用程式版本，不包含其他關於你的資訊。
- 回報問題：在你按下「傳送」之前，不會送出任何內容。回報內容包含你的訊息、你填寫的電子郵件、應用程式與 macOS 版本、Mac 機型、鍵盤類型、你的 FnCaps 設定、你的輸入方式、最近的活動記錄，以及只用於每日上限的隨機安裝編號。內容不包含你輸入的文字、序號或其他裝置 ID。你可以在傳送前查看全部內容。回報會存放在只有開發者能讀取的私人儲存庫中。
- 回報限制：每個安裝每天五次，同一網路位址每分鐘五次。

## 已知限制

- 密碼欄位：macOS 讓密碼欄位保持英文，因此 FnCaps 不會在其中切換語言，按住 Caps Lock 也不會開啟 Caps Lock。
- Control+Space：FnCaps 開啟時不會切換輸入方式。關閉或結束 FnCaps 後會恢復正常。
- 語言指示器：快速按下按鍵時，macOS 在游標旁顯示的小指示器可能與實際使用的語言不同。選單列顯示的才是正確的。
- 英文配置：FnCaps 將 ABC 和 U.S. 視為英文。ABC – AZERTY 和 ABC – QWERTZ 計為法文和德文。
- Karabiner-Elements 和 gksdud：這些應用程式會變更相同的按鍵。使用 `caps_lock` 的 Karabiner 規則會在 FnCaps 看到按鍵之前先取走它。其中一個應用程式執行時，FnCaps 會顯示警告。
- 未測試但預期可用：拔除並重新接上外接鍵盤、macOS 14 到 26，以及 Apple silicon MacBook Air 以外的 Mac。

## 復原

如果 Caps Lock 無法使用：

- 在 FnCaps 中，從選單列圖示選擇「還原按鍵」，或在「設定 > 一般」中按「立即還原」。這會將 Caps Lock 與輸入方式快速鍵還原成 FnCaps 之前的狀態。
- 如果 FnCaps 未執行，例如當機之後，Caps Lock 可能仍維持重新對應而沒有作用。在終端機中清除重新對應，然後再次打開 FnCaps：

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```

- 如果你複製了此儲存庫，此腳本會清除重新對應，並還原輸入方式快速鍵：

  ```sh
  scripts/caps-recover.sh --restore
  ```

結束 FnCaps 後，如果 Control+Space 仍無法切換輸入方式，請檢查系統設定 > 鍵盤 > 鍵盤快速鍵 > 輸入方式 >「選取上一個輸入方式」。「還原按鍵」會將其還原成 FnCaps 之前的狀態。

## 解除安裝

請先結束 FnCaps。結束時會將 Caps Lock 與輸入方式快速鍵還原成原本的狀態。然後執行：

```sh
brew uninstall --cask fncaps
```

或將 `FnCaps.app` 從 `/Applications` 移到垃圾桶。如要一併移除設定，請使用 `brew uninstall --zap --cask fncaps`。

## 從原始碼建置

```sh
swift build
scripts/build-app.sh
```

`scripts/build-app.sh` 會建立 `build/FnCaps.app`。若有「FnCaps Dev Local」憑證，會使用該憑證簽署，否則使用臨時簽章。使用臨時簽章時，macOS 會在每次建置後再次要求輔助使用權限。`scripts/make-local-identity.sh` 會建立本機憑證。

## 參與貢獻

歡迎提出問題與提取要求。應用程式與本 README 已翻譯成十種語言。大多數翻譯未經母語人士校對，因此特別歡迎翻譯修正。

## 授權條款

MIT。請參閱 [LICENSE](LICENSE)。
