# Car Simulator / Автосимулятор

A playable 3D car driving simulator for Windows, built with **Godot 4.4**.

Играбельный 3D-симулятор вождения для Windows на **Godot 4.4**.

**v1.3.4** — **Cornering feel**: keep power while steering+throttle (no scrub-to-stop), softer yaw kill, lower angular damp & tire friction (~4.0). Also: FPS yellow-wall fix (1.3.3), horizon look, hard reset, visual damage.

Player car: Kenney CC0 sedan-sports (scaled ~4 m) on `VehicleBody3D` + `VehicleWheel3D` with engine RPM, torque curve, gears (R + 1–5), **hold-to-turn** steering, brakes, handbrake, suspension travel, tire slip, anti-spin, weight transfer, **visual damage** (mesh crumple / bent panels / smoke — not soft-body), cliff freefall → wreck → auto-restart. Circuit: ~20 m asphalt, gravel runoff, cliff void (no infinite ground plane).

Машина игрока: седан Kenney (CC0) с видом от первого лица, плавным рулём, визуальными повреждениями и авто-рестартом после критического краша / падения с обрыва.

![Godot](https://img.shields.io/badge/Godot-4.4.1-478cbf) ![License](https://img.shields.io/badge/license-MIT-green) ![Version](https://img.shields.io/badge/version-1.3.4-blue)

## Play / Как играть

### Download the Windows installer (GitHub Actions)

1. Open **Actions** on this repository: [github.com/ivanivorontsov-sudo/car-simulator/actions](https://github.com/ivanivorontsov-sudo/car-simulator/actions)
2. Select workflow **Build Windows installer**
3. Open a successful run (or trigger **Run workflow**)
4. Download the artifact **`car-simulator-windows-installer`**
5. Unzip it and run **`CarSimulatorSetup.exe`** (NSIS). If the workflow fell back to a zip, extract it and run `CarSimulator.exe` or `Start.bat`.

### Скачать установщик Windows (GitHub Actions)

1. Откройте **Actions**: [github.com/ivanivorontsov-sudo/car-simulator/actions](https://github.com/ivanivorontsov-sudo/car-simulator/actions)
2. Выберите workflow **Build Windows installer**
3. Откройте успешный запуск (или нажмите **Run workflow**)
4. Скачайте артефакт **`car-simulator-windows-installer`**
5. Распакуйте и запустите **`CarSimulatorSetup.exe`**. Если вместо установщика лежит zip — распакуйте и запустите `CarSimulator.exe` или `Start.bat`.

## Controls / Управление

| Key / Клавиша | Action / Действие |
| --- | --- |
| **W** / **↑** | Throttle / Газ |
| **S** / **↓** | Brake / reverse / Тормоз / задний ход |
| **A D** / **← →** | Hold to steer (smooth) / Удерживать для поворота |
| **Space** | Brake / Тормоз |
| **Shift** | Handbrake / Ручник |
| **C** | Chase ↔ FPS driver view / Камера (преследование ↔ FPS) |
| **R** | Reset to start / Сброс на старт |
| **Esc** | Pause / Пауза |
| **Q / E** | Manual downshift / upshift / Переключение передач вручную |
| **F11** | Fullscreen / Полный экран |
| Gamepad | Left stick steer, RT throttle, LT brake, B handbrake, Y camera, X reset, Start pause |

HUD: tachometer, gear, speed (km/h), RPM bar, optional **damage** bar. Critical wreck / cliff fall shows a countdown then auto-restarts (~5 s).

## Run from source / Запуск из исходников

Requirements: [Godot 4.4.x](https://godotengine.org/download) (tested with **4.4.1**).

```text
1. Install Godot 4.4.1 (standard, not .NET).
2. Clone this repo.
3. Godot → Import → open project.godot
4. Press F5. Main scene is scenes/main.tscn.
```

Требования: Godot 4.4.x (проверено на **4.4.1**).

```text
1. Установите Godot 4.4.1 (обычный, не Mono/.NET).
2. Клонируйте репозиторий.
3. Godot → Import → откройте project.godot
4. F5. Главная сцена: scenes/main.tscn.
```

## Physics & damage / Физика и повреждения

- Godot `VehicleBody3D` + four `VehicleWheel3D` (RWD, front steer)
- Engine: idle 900 RPM, redline 7500, peak torque ~400 N·m @ 4800 RPM
- Gearbox: reverse + 1–5, final drive 3.55, auto up/downshift
- Progressive hold-to-turn steering (ease-in/out) + speed-sensitive max angle; cabin wheel rotates in sync
- Surface grip: asphalt / gravel / grass apron
- Suspension travel, lower CG, anti-roll, yaw damping (less tippy, fewer random spins)
- **Visual damage system**: impact impulse / hard landings crumple mesh vertices, bend panels, optional detached bumper / broken glass; smoke & sparks at high damage; engine power loss. Critical damage or cliff fall → wreck state → **~5 s auto-restart**

This is **not** a soft-body / BeamNG simulator. Deformation is a visual approximation on a rigid-body vehicle.

Это **не** soft-body как BeamNG. Повреждения — визуальная аппроксимация на твёрдом теле.

## Project layout / Структура

```text
scenes/           Main, car, HUD, pause
scripts/          Vehicle, world, camera, UI
assets/models/    Kenney cars, trees, track props
assets/textures/  Poly Haven asphalt + grass
assets/hdri/      Poly Haven sky
assets/audio/     Engine + skid + impact loops
installer/        NSIS script + Start.bat fallback
.github/workflows/build-installer.yml
```

## License

Code: MIT (see `LICENSE`). Third-party assets: see `CREDITS.md`.
