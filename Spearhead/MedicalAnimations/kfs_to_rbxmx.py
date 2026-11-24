"""Turn the KeyframeSequence JSON dumped from Studio into one .rbxmx per animation."""
import json, sys, pathlib
from xml.sax.saxutils import escape

STYLE = {"Linear": 0, "Constant": 1, "Elastic": 2, "Cubic": 3, "Bounce": 4, "CubicV2": 5}
DIR = {"In": 0, "Out": 1, "InOut": 2}
PRIO = {"Idle": 0, "Movement": 1, "Action": 2, "Action2": 3, "Action3": 4, "Action4": 5, "Core": 1000}
ref = 0


def item(cls, props, kids):
    global ref
    ref += 1
    return f'<Item class="{cls}" referent="RBX{ref}"><Properties>{props}</Properties>{"".join(kids)}</Item>'


def pose(p):
    names = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
    cf = "".join(f"<{n}>{v!r}</{n}>" for n, v in zip(names, p["cf"]))
    props = (f'<string name="Name">{escape(p["name"])}</string><CoordinateFrame name="CFrame">{cf}</CoordinateFrame>'
             f'<token name="EasingDirection">{DIR[p["dir"]]}</token><token name="EasingStyle">{STYLE[p["style"]]}</token>'
             f'<float name="Weight">{p["weight"]!r}</float>')
    return item("Pose", props, [pose(k) for k in p["kids"]])


raw = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
if raw.startswith('"'):
    raw = json.loads(raw)
seqs = json.loads(raw)
out_dir = pathlib.Path(sys.argv[2])
out_dir.mkdir(parents=True, exist_ok=True)
for s in seqs:
    kfs = []
    for k in s["keyframes"]:
        props = f'<string name="Name">{escape(k["name"])}</string><float name="Time">{k["time"]!r}</float>'
        kfs.append(item("Keyframe", props, [pose(p) for p in k["poses"]]))
    props = (f'<string name="Name">{escape(s["name"])}</string><bool name="Loop">{str(s["loop"]).lower()}</bool>'
             f'<token name="Priority">{PRIO[s["priority"]]}</token>')
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
           + item("KeyframeSequence", props, kfs) + "</roblox>")
    path = out_dir / f'{s["name"]}.rbxmx'
    path.write_text(xml, encoding="utf-8")
    print(path, len(s["keyframes"]), "keyframes")
