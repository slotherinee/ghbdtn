# ghbdtn

Приложение для macOS в строке меню, которое переводит текст, набранный не в той раскладке — выдели текст и нажми хоткей.

## Как пользоваться

1. Выдели текст в любом приложении
2. Нажми **двойной ⌃ Control** (или другой хоткей из настроек)
3. Текст автоматически переведётся в нужную раскладку

`"ghbdtn"` → `"привет"`, `"привет"` → `"ghbdtn"`, `"Привет ghbdtn"` → `"Hello привет"`

## Установка

### Скачать готовый .dmg

Открой [Releases](../../releases) → скачай последний `ghbdtn-vX.X.X.dmg` → перетащи `ghbdtn.app` в папку **Программы**.

> **Если macOS пишет «Не удалось открыть»:**
> Системные настройки → Конфиденциальность и безопасность → пролистай вниз → нажми **«Всё равно открыть»**

### Собрать из исходников

```bash
git clone https://github.com/yourusername/ghbdtn.git
cd ghbdtn/ghbdtn
open ghbdtn.xcodeproj
```

Собери и запусти через Xcode (`⌘R`). При первом запуске появится запрос на доступ к **Специальным возможностям** — без него хоткей и замена текста не работают.

## Требования

- macOS 13+
- Минимум 2 раскладки клавиатуры в настройках системы

## Настройки

Клик на иконке в строке меню → **Настройки…**

- **Горячая клавиша** — двойной ⌃ Control, ⌥ Option+Пробел или своё сочетание
- **Режим переключения** — между двумя раскладками или циклически по выбранным
- Выбор раскладок для переключения

## Как работает

`сохранить буфер → ⌘C → перевести символы → ⌘V → восстановить буфер`

Перевод побуквенный и двунаправленный — каждый символ транслируется независимо, направление определяется автоматически.

---

A macOS menu bar app that translates text typed in the wrong keyboard layout — select and press a hotkey.

**Usage:** Select text → press **double ⌃ Control** → text is retranslated in place.

**Install:** Download the `.dmg` from [Releases](../../releases) or clone and build in Xcode.

> **If macOS says it can't be opened:** System Settings → Privacy & Security → scroll down → **"Open Anyway"**

**Requirements:** macOS 13+, at least 2 keyboard layouts installed.
