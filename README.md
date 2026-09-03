# Car Simulator / Автосимулятор

A playable 3D car driving simulator for Windows, built with **Godot 4.4**.

Играбельный 3D-симулятор вождения для Windows на **Godot 4.4**.

Player car: Kenney CC0 sedan-sports (scaled to a ~4 m wheelbase) on `VehicleBody3D` + `VehicleWheel3D` with engine RPM, a torque curve, gears (R + 1–5, automatic with Q/E manual), steering, brakes, handbrake, suspension, tire slip, weight transfer, and tire marks. Circuit has asphalt, rumble strips, gravel runoff at the same height as the road, then a sloped apron — leaving the tarmac does not trap the chassis.

Машина игрока: седан Kenney (CC0), увеличенный до колёсной базы ~4 м, на `VehicleBody3D` + `VehicleWheel3D` с оборотами, кривой момента, передачами (R + 1–5), рулём, тормозами, ручником, подвеской и следами шин. Обочина на той же высоте, что и асфальт — машина не застревает на кромке.

![Godot](https://img.shields.io/badge/Godot-4.4.1-478cbf) ![License](https://img.shields.io/badge/license-MIT-green)

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
| **A D** / **← →** | Steer / Руль |
| **Space** | Brake / Тормоз |
| **Shift** | Handbrake / Ручник |
| **C** | Chase / hood camera / Камера (преследование / капот) |
| **R** | Reset to start / Сброс на старт |
| **Esc** | Pause / Пауза |
| **Q / E** | Manual downshift / upshift / Переключение передач вручную |
| **F11** | Fullscreen / Полный экран |
| Gamepad | Left stick steer, RT throttle, LT brake, B handbrake, Y camera, X reset, Start pause |

HUD: analog-style **tachometer**, **gear**, speed in **km/h**, RPM bar. Camera: chase (looks into corners, FOV grows with speed) and a hood cam that sits in the cabin, not glued to the hood.

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

## Physics / Физика

- Godot `VehicleBody3D` + four `VehicleWheel3D` (RWD, front steer)
- Engine: idle 900 RPM, redline 7500, peak torque ~455 N·m @ 4800 RPM
- Gearbox: reverse + 1–5, final drive 3.73, auto up/downshift
- Speed-sensitive steering, split front/rear brakes, handbrake cuts rear grip
- Stiffer damped suspension, low CG, extra downforce (simcade, still not BeamNG)
- Driveable gravel shoulder at road height + sloped apron; outer Armco well past the runoff; no inner concrete wall
- Speed displayed in km/h; R resets to the start/finish grid

This is **not** a soft-body simulator (BeamNG). It is a rigid-body vehicle model with a drivetrain layer.

Это не soft-body как BeamNG, а твёрдое тело с надстройкой трансмиссии.

## Project layout / Структура

```text
scenes/           Main, car, HUD, pause
scripts/          Vehicle, world, camera, UI
assets/models/    Kenney cars, trees, track props
assets/textures/  Poly Haven asphalt + grass
assets/hdri/      Poly Haven sky
assets/audio/     Engine + skid loops
installer/        NSIS script + Start.bat fallback
.github/workflows/build-installer.yml
```

## License

Code: MIT (see `LICENSE`). Third-party assets: see `CREDITS.md`.
