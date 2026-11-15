# FnCaps

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 简体中文 | [繁體中文](README.zh-Hant.md) | [Українська](README.uk.md) | [Русский](README.ru.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md)

FnCaps 是一款 macOS 菜单栏应用，适合使用三种或更多输入法、并且觉得在它们之间切换很慢的人。

macOS 只提供一个按键，依次轮换所有输入法。当输入法有三种或更多时，你需要一直按到想要的语言出现，看一眼菜单栏，然后再按一次。

FnCaps 把输入法分到两个按键上：Caps Lock 和 fn（🌐）。

- 每个按键都有自己的列表，只在该列表内切换。
- 语言放在哪个按键上由你决定。例如，把英文放在 Caps Lock 上，把其他语言放在 fn 上。
- 一个长列表变成两个短列表。按照 FnCaps 推荐的布局，想要的语言只差一两次按键，你的输入不会被打断。
- 语言更多时，你可以给某个输入法指定单独的快捷键，直接切过去。
- Caps Lock 切换没有延迟。按住它则像往常一样打开或关闭 Caps Lock。

> **首次启动：** macOS 会拦截 FnCaps 一次，因为它没有经过 Apple 公证。打开「系统设置」>「隐私与安全性」，点按「仍要打开」。具体步骤见[仍要打开](#open-anyway)。

> FnCaps 在 1.0 之前处于早期开发阶段。

## 系统要求

- macOS 14 Sonoma 或更高版本，Apple silicon 或 Intel
- 辅助功能权限。FnCaps 需要它来识别 fn 和 Caps Lock 的按下。

## 安装

### Homebrew

```sh
brew install --cask Seo650/tap/fncaps
```

### GitHub Releases

1. 从 [Releases](https://github.com/Seo650/FnCaps/releases/latest) 下载最新的 `FnCaps-x.y.z.zip`。
2. 解压缩。
3. 把 `FnCaps.app` 移到 `/Applications`。

## 首次启动

<a id="open-anyway"></a>

### 仍要打开

FnCaps 使用自己的证书签名，没有经过 Apple 公证，因此 macOS 会拦截首次启动。这只会发生一次。

1. 打开 FnCaps。macOS 提示无法验证此应用。点按「完成」。
2. 打开「系统设置」>「隐私与安全性」。
3. 在「安全性」下，点按「仍要打开」。
4. 输入密码或使用 Touch ID，然后点按「打开」。

「仍要打开」按钮只在启动被拦截后出现，大约保留一小时。如果它不见了，请再次打开 FnCaps。如果你更喜欢命令行，下面的命令可以解除拦截：

```sh
xattr -dr com.apple.quarantine /Applications/FnCaps.app
```

### 设置

FnCaps 打开后会引导你完成辅助功能权限和按键布局的设置。FnCaps 需要该权限来识别 fn 和 Caps Lock 的按下。之后你可以在 FnCaps 设置中更改所有内容。

## 更新

FnCaps 每天检查一次新版本。要安装新版本，请打开 FnCaps 设置，进入「关于FnCaps」，点按「更新」。在你点按「更新」之前不会安装任何内容。Homebrew 用户也用同样的方式更新。

更新会保留辅助功能权限，因为每个版本都用同一证书签名。

## FnCaps 发送的内容

FnCaps 不会记录你输入的内容。它只在两种情况下连接互联网。

- 更新检查：FnCaps 每天向 GitHub API 请求一次最新版本。该请求只包含应用版本，不包含关于你的其他信息。
- 报告问题：在你点按「发送」之前，不会发送任何内容。报告包含你的消息、你填写的电子邮件（如果填写）、应用和 macOS 版本、Mac 机型、键盘类型、你的 FnCaps 设置、你的输入法、最近的活动日志，以及仅用于每日限额的随机安装编号。报告不包含你输入的内容、序列号或其他设备 ID。发送前你可以阅读全部内容。报告存放在只有开发者可以读取的私有仓库中。
- 报告限制：每个安装每天五次，同一网络地址每分钟五次。

## 已知限制

- 密码栏：macOS 会让密码栏保持英文，因此 FnCaps 不会在那里切换语言，按住 Caps Lock 也不会打开 Caps Lock。
- Control+Space：在 FnCaps 开启时不切换输入法。关闭或退出 FnCaps 后它会恢复工作。
- Caps Lock 灯：通过按住按键打开 Caps Lock 时，键上的灯保持熄灭。大写字母仍会正常输入。
- 语言指示器：快速按键时，macOS 在光标旁显示的小指示器可能显示的语言与正在使用的语言不同。菜单栏会显示正确的那一个。
- 正在组字：如果按下 fn 时某个韩文、日文或中文字符仍在组字中，该字符可能会丢失。
- 英文布局：FnCaps 把 ABC 和 U.S. 视为英文。ABC – AZERTY 和 ABC – QWERTZ 分别视为法文和德文。
- Karabiner-Elements 和 gksdud：这些应用会更改相同的按键。使用 `caps_lock` 的 Karabiner 规则会在 FnCaps 看到按键之前将其取走。在其中一个应用运行时，FnCaps 会显示警告。
- 未测试，预计可以工作：拔出并重新连接外接键盘、macOS 14 到 26，以及 Apple silicon MacBook Air 以外的 Mac。

## 恢复

如果 Caps Lock 停止工作：

- 在 FnCaps 中，从菜单栏图标选择「恢复按键」，或者在「设置」>「通用」中点按「立即恢复」。这会把 Caps Lock 和输入法快捷键恢复到 FnCaps 之前的状态。
- 如果 FnCaps 没有运行，例如崩溃之后，Caps Lock 可能仍处于重新映射状态而什么都不做。在「终端」中清除映射，然后再次打开 FnCaps：

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```

- 如果你克隆了这个仓库，脚本会清除映射，并同时恢复输入法快捷键：

  ```sh
  scripts/caps-recover.sh --restore
  ```

如果你退出 FnCaps 后 Control+Space 仍不切换输入法，请检查「系统设置」>「键盘」>「键盘快捷键」>「输入法」>「选择上一个输入法」。「恢复按键」会把它恢复到 FnCaps 之前的状态。

## 卸载

请先退出 FnCaps。退出会把 Caps Lock 和输入法快捷键恢复到原来的状态。然后运行：

```sh
brew uninstall --cask fncaps
```

或者把 `FnCaps.app` 从 `/Applications` 移到「废纸篓」。如果要连同设置一起删除，请使用 `brew uninstall --zap --cask fncaps`。

## 从源码构建

```sh
swift build
scripts/build-app.sh
```

`scripts/build-app.sh` 会生成 `build/FnCaps.app`。如果存在「FnCaps Dev Local」证书，它会用该证书签名，否则使用 ad-hoc 签名。使用 ad-hoc 签名时，每次构建后 macOS 都会再次要求辅助功能权限。`scripts/make-local-identity.sh` 会创建本地证书。

## 参与贡献

欢迎提交问题和拉取请求。应用和本 README 已翻译成十种语言。大多数翻译没有经过母语者检查，因此特别欢迎修正翻译。

## 许可证

MIT。参见 [LICENSE](LICENSE)。
