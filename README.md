# htop-kde-plasma6

[![Plasma](https://img.shields.io/badge/KDE%20Plasma-6-blue)](https://kde.org/plasma-desktop)
[![License: GPL](https://img.shields.io/badge/License-GPL-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux-orange)](https://github.com/listellodavide/htop-kde-plasma6)

A **modern htop-like system monitor widget** for **KDE Plasma 6**.  
Monitor CPU, memory, processes, disk I/O, and network usage directly from your desktop panel.

![Widget Screenshot](screenshot.png) <!-- Replace with actual screenshot path -->

---

## ✨ Features

- **Real-time process monitoring** with CPU, memory, disk, and network stats.
- **Sortable & filterable process list** (by name, PID, CPU, memory, etc.).
- **Quick process kill** directly from the widget.
- **Configurable columns** and update intervals.
- **Clean Plasma 6 integration** with theme support.

---

## 📦 Installation

### 1. Clone the repository
```bash
git clone https://github.com/listellodavide/htop-kde-plasma6.git
cd htop-kde-plasma6
```

### 2. Install the widget
```bash
kpackagetool6 --install .
```
> Use `--upgrade` instead of `--install` if updating.

### 3. Restart Plasma shell (if needed)
```bash
kquitapp6 plasmashell && kstart6 plasmashell
```

---

## 🛠 Development Setup

1. Modify files in the `contents/` directory.
2. Reinstall with:
   ```bash
   kpackagetool6 --upgrade .
   ```
3. Restart Plasma shell to apply changes.

---

## 📂 Project Structure

```
htop-kde-plasma6/
├── contents/
│   ├── ui/            # QML UI files
│   ├── scripts/       # Data fetching scripts
│   └── config/        # Config QML files
├── metadata.desktop   # Widget metadata
└── LICENSE
```

---

## 💡 Requirements

- KDE Plasma 6
- `kpackagetool6`
- Python 3 (for system data collection scripts)
- Linux CLI tools: `ps`, `df`, `free`, etc.

---

## 📚 Documentation

https://doc.qt.io/qt-6/qtqml-syntax-basics.html

https://develop.kde.org/docs/plasma/widget/


---

## 📜 License

Licensed under the **Apache License v2**. See the [LICENSE](LICENSE) file.

---

## 🙌 Contributing

PRs and issues are welcome. Please open an issue before large changes.

---

## 📧 Author

**Davide Listello**  
📧 [davide.listello@gmail.com](mailto:davide.listello@gmail.com)  
🌐 [GitHub Profile](https://github.com/listellodavide)
