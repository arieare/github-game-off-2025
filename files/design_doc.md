# 🏎️ TAMIYA WAVE — Game Design Document (Updated)

## 🎯 Concept Overview
**Title:** *TAMIYA WAVE*  
**Genre:** Simulation / Roguelite / Strategy Tuning Game  
**Theme:** Fine-tuning miniature racing cars for procedural wave tracks  
**Core Loop:** Collect → Tune → Test → Optimize → Compete

The game explores the interplay between **momentum**, **force balance**, and **endurance**. Each track is a modular wave of straights, corners, lane switches, and risers. Players optimize builds for each run using limited spare parts, trying to finish within time and energy constraints.

---

## ⚙️ Design Principles
1. **Extensible:** New track segment types, car forces, and spare parts can be added without breaking the system.
2. **Modular:** Systems (track, car, simulation, visuals, UI) communicate through clear data contracts.
3. **Deterministic:** The simulation produces consistent results given the same parameters.
4. **Readable Data:** Track and car models are pure data first, simulation second.

---

## 🚗 Core Gameplay Loop
1. **Collect spare parts:** Win or buy motors, gears, bodies, and batteries.
2. **Inspect the track:** Each procedural track comes with rules and modifiers.
3. **Fine-tune the car:** Assemble parts within slot limits and energy budgets.
4. **Simulate the run:** Observe how forces, battery, and handling interact.
5. **Earn rewards:** Based on lap time, completion, and leftover energy.
6. **Progression:** Unlock new modules, rarer parts, or full cars for disassembly.

---

## 🧩 Track System

### 1. Token Grammar
Each segment is a compact code:

| Code | Type | Notes |
|------|------|-------|
| `ST` | Start | Beginning of lap, defines spawn position |
| `S[:len]` | Straight | Baseline segment with friction & slope = 0 |
| `CL[:rX][,bY]` | Corner Left | Left curve, optional radius (r) & bank (b) |
| `CR[:rX][,bY]` | Corner Right | Right curve |
| `LSxy` | Lane Switch | Switch from lane x → y |
| `R[:±ang][:len]` | Raiser | Elevation up/down, affects gravity and battery |
| `FN` | Finish | End of lap, triggers lap completion |

Example:
```json
{
  "meta": {
    "direction": "CW",
    "lanes": 3,
    "lane_width": 0.08,
    "start_lane": 1,
    "laps_required": 3,
    "lap_lane_goal": "ALL",
    "strict_finish_lane": false
  },
  "tokens": [
    "ST", "S:1.4", "CL:r1.4,b8", "S:0.8", "LS12", "R:+10:0.5", "R:-10:0.5",
    "CR:r1.0,b6", "S:0.6", "LS23", "S:1.0", "CR:r1.2,b5", "S:0.8",
    "R:+6:0.4", "R:-6:0.4", "CL:r0.9,b10", "S:1.2", "LS31", "S:0.8", "FN"
  ]
}
```

### 2. Segment Compilation
Each token expands to a structure:
```json
{
  "type": "CORNER",
  "dir": "L",
  "len": 0.8,
  "kappa": 0.714,
  "bank": 8,
  "μ": 1.0
}
```
Other fields (e.g., `start`, `end`, `slope`) are computed cumulatively.

### 3. Segment Length and Simulation
Segment length defines how long forces act on the car during integration. The simulation:
- Advances `s += v * dt`
- Queries segment by `track.at(s)`
- Normalizes local position `u = (s - seg.start) / seg.len`
- Applies segment-specific signals (curvature, slope, friction)
- Splits steps if crossing boundaries

This ensures physics effects scale with distance traveled.

### 4. Lane Logic
- Track meta defines number of lanes.
- Car occupies a single lane; `LSxy` triggers lane change events.
- Each lap requires visiting all lanes at least once.
- Lap completion: crossing `FN` after satisfying lane visit condition.

---

## 🧠 Car System

### 1. Forces
- **Forward Force (Ff):** Motor output → speed
- **Downward Force (Df):** Weight & aerodynamics → grip
- **Lateral Torque (Lt):** Side rollers, stability → resistance to derailment

All three are tunable through parts.

### 2. Battery Model
Battery acts as the *energy constraint*.
```gdscript
car.B -= (0.05 * throttle^2 + 0.001 * v^2) * dt / efficiency
```
Motor force fades with charge:
```gdscript
F_drive = F_max * (car.B / 100)
```
When depleted, car coasts with drag only.

### 3. Car Parts (Data Example)
```json
{
  "id": "motor_turbo_x",
  "motor_power": 1.4,
  "motor_efficiency": 0.72,
  "battery_mod": -0.15,
  "weight_mod": +0.05
}
```

### 4. Progression
Players unlock new motors, gears, and bodies, each shifting the trade-off triangle:
**Speed ↔ Stability ↔ Endurance**

---

## 🔢 Simulation Overview

### Step-by-Step Loop
```gdscript
var seg = track.at(car.s)
var u = (car.s - seg.start) / seg.len
var sig = track.signal(seg, u)

# Forces
var F_drive = motor_force(car, throttle)
var F_drag = 0.5 * rho * drag_coeff(car) * car.v^2
var F_roll = mass * g * c_rr
var F_grade = mass * g * sin(sig.slope)
var a_long = (F_drive - F_drag - F_roll - F_grade) / mass

# Integrate
car.v += a_long * dt
car.s += car.v * dt
car.B -= drain_rate * dt
```

### Boundary Splitting
If `car.s + ds > seg.end`, split time step to land precisely on boundary, then continue with remaining time in next segment.

### Lane & Lap Logic
- On `LANE_SWITCH`, update `car.lane` and apply minor speed shave.
- On `FINISH`, increment `laps_completed` if all lanes visited.
- On `derail`, respawn at `START` with partial battery refund.

---

## 🧩 System Architecture

### Modules
| Module | Responsibility | Communication |
|---------|----------------|----------------|
| **TrackModel** | Defines geometry & metadata | Provides `at(s)` and `signal(seg,u)` to Simulation |
| **CarModel** | Stores car state (v, s, B, lane, parts) | Provides force parameters to Simulation |
| **SimulationController** | Advances physics & handles logic | Talks to both TrackModel & CarModel |
| **PartSystem** | Defines all available parts | Exposes stats for assembly UI |
| **UIController** | Shows telemetry, lap, and battery | Reads-only from SimulationController |

### Flow Diagram
```
Player Input → CarConfig → SimulationController
                         ↓
             TrackModel ←→ CarModel
                         ↓
                      UI Output
```

All systems are loosely coupled; changing track structure or adding new part attributes does not break the simulation loop.

---

## 🧮 Example: Process Function
Key logic snippet connecting car & track:
```gdscript
func _process(delta):
    _acc += delta
    while _acc >= DT and !car.finished:
        var seg = track.at(car.s)
        var u = (car.s - seg.start) / max(seg.len, 1e-6)
        var sig = track.signal(seg, u)

        var throttle = car.B > 0.0 ? 1.0 : 0.0
        var F_drive = _motor_force(car, throttle)
        var F_drag = 0.5 * rho * drag_coeff(car) * car.v * car.v
        var F_roll = mass * g * c_rr
        var a_long = (F_drive - F_drag - F_roll) / mass

        car.v = max(0, car.v + a_long * DT)
        car.s += car.v * DT
        car.B = max(0, car.B - (0.05 * throttle^2 + 0.001 * car.v^2) * DT)

        if seg.type == "LANE_SWITCH" and car.lane == seg.from:
            car.lane = seg.to
        if seg.type == "FINISH":
            car.laps_completed += 1
            if car.laps_completed >= track.meta.laps_required:
                car.finished = true

        _acc -= DT
```

---

## 🧱 Extensibility Notes
- Adding a new **force**: Add new property in `CarModel`, modify `_apply_forces()`.
- Adding a new **segment**: Add token → compile rule in `TrackCompiler`, define new signal parameters.
- Adding a new **part type**: Append JSON schema, modify UI to expose stat mapping.

All other modules remain untouched.

---

## 🧭 Summary
**TAMIYA WAVE** simulates the poetic dance of momentum and endurance. Tracks are procedural waveforms of curves, slopes, and switches. Cars are modular equations of force, grip, and battery. The player’s mastery lies in reading the rhythm between these two systems — surfing the wave rather than fighting it.

