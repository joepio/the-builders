# The Builders

Couch co-op construction chaos for 1 to 8 players. Everyone shares one
building site, seen from above. Walk to a machine, hop in, and get the job
done together: clear the junk, dig the foundation pit, haul the dirt away,
pump concrete into the pit, then forklift the house modules to the crane and
stack a tiny house.

The machines are toys, but they don't all drive like toys. The bulldozer has
a lever per track, the forklift steers with its rear wheels, the excavator
uses real two-stick digger controls and the crane's load swings on its rope.
That is the point.

![Mid-job](docs/screenshots/mid-job.png)

## The job: a tiny house

| Step | Who | How |
| --- | --- | --- |
| Clear the junk | Bulldozer | Push the sofa, tyres, slabs and the old fridge into the **DUMP** hole |
| Dig the foundation pit | Excavator | Scoop the nine dirt cells down to the pit floor |
| Haul the dirt | Excavator + dump truck | Dump into the truck, drive it to the hole, tip the bed. Dirt spilled back into the pit fills it again |
| Pour the concrete | Concrete truck + builder on foot | Park the mixer near the pit, press Y to start the pump, then grab the hose on foot and pour every dug cell full. The hose only reaches 11 m and missed concrete splats on the sand |
| Stack the house | Forklifts + crane + builders | Forklift modules from **DELIVERIES** to **CRANE PICKUP**, crane them onto the dotted ghosts (four below, two on top, then the roof). Nothing snaps: a builder on foot presses A next to a lowered module to bolt it in exactly where it stands, up to 1 m off and 20 degrees twisted. Sloppy crane work makes a wonky house |
| PUR every gap | Builders on foot | Grab a foam gun from the PUR crate and spray every glowing gap where two parts meet. Wonkier joins need more foam. The job ends with a neatness score |

A module that falls in the dump is reordered and delivered again. The timer
gives three stars under 8 minutes and two under 12.

## Controls

On foot: left stick walks, **A** picks up a tool (concrete hose, foam
gun), bolts a lowered module in, or climbs into the nearest free machine, **B** climbs out or puts the tool down,
**RT** or **A** uses the tool. Fast machines knock builders over. Hold **X** in a machine to
show its controls in your player card.

| Machine | Controls |
| --- | --- |
| Bulldozer | LT / LB: left track forward / back, RT / RB: right track forward / back, right stick: lift and angle the blade |
| Excavator | Left stick: swing / arm in-out, right stick: boom / bucket curl, LT / LB and RT / RB: tracks, same as the bulldozer. Dirt stays in while the bucket faces up |
| Forklift | Left stick: steer (rear wheels), RT / LT: drive / reverse, right stick: forks |
| Dump truck | Left stick: steer, RT / LT: drive / reverse, Y or RB: tip the bed |
| Concrete truck | Left stick: steer, RT / LT: drive / reverse, Y: pump on / off |
| Tower crane | Left stick: rotate / trolley, right stick: hoist, A: hook on / let go, LB / RB: turn the load |

The GameNight setting **Machine controls: easy** gives the bulldozer one-stick
driving, the forklift normal steering and damps the crane's swing.

Without GameNight, press A on a pad, Space (WASD + IJKL keyboard player) or
Enter (arrows + numpad player) to join. Esc pauses.

## Run

```sh
godot --path .                     # empty site, players drop in
godot --path . -- --demo           # five machines with scripted drivers
godot --path . -- --demo --pose    # frozen mid-job moment for screenshots
tools/shot.sh out.png --demo --pose --shot-time=2.5   # headless screenshot (xvfb)
```

`--stage=dug|half|built` jumps the job forward, `--cam=x,z,distance,tilt`
moves the camera.

## Tests

```sh
godot --headless --path . --script tests/job_check.gd   # every machine does its job step
python3 tests/lifecycle.py --godot godot                # managed launch against a fake GameNight host
```

`job_check.gd` drives each machine with scripted sticks on a real site:
scooping and spilling dirt, lifting and reversing with a pallet, craning a
module onto its slot (and the load swinging when slewing), bulldozing junk
into the dump and tipping the truck bed.

## GameNight

Uses the [GameNight Godot addon](https://github.com/ontola/gamenight/tree/main/sdk/godot)
in `addons/gamenight`. CI fails when the copy drifts from the SDK; update it
with `python sdk/godot/sync.py path/to/the-builders` from a gamenight checkout.
Under GameNight, seats become builders, the host owns pause, and a finished
house reports the round and starts the next job.

## Code

- `src/main.gd`: players, camera, GameNight lifecycle, demo and screenshots
- `src/site.gd`: the level and the job: ground, pit cells, dump, slots, deliveries
- `src/machine.gd`: shared rigid-body machine with arcade drive helpers
- `src/bulldozer.gd`, `excavator.gd`, `forklift.gd`, `dump_truck.gd`, `crane.gd`: the machines
- `src/concrete_truck.gd`, `hose.gd`, `foam_gun.gd`, `foam.gd`, `tool.gd`: the mixer and its hose, the PUR gun and its foam, tools builders carry
- `src/ruts.gd`, `decor.gd`: tracks in the sand, scenery
- `src/module.gd`: house modules and the roof on pallets
- `src/worker.gd`: builders on foot
- `src/hud.gd`, `src/toy.gd`: interface and the primitive toy look
