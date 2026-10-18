"""Encode the standalone preview's native AppKit renders, without changing artwork."""
from pathlib import Path
import hashlib
import json
import math
import sys
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[2]
renders = root / 'build/desktop-pet-interaction/renders'
output = Path(sys.argv[1]) if len(sys.argv) > 1 else renders.parent / 'gifs'
output.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc', 23)
small = ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc', 16)


def compose(file, title, x=220, y=65):
    canvas = Image.new('RGB', (700, 350), '#f4f2ed')
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 16), title, font=font, fill='#252526')
    draw.text((24, 318), 'YUI Neko · 原生互動預覽', font=small, fill='#6a6864')
    sprite = Image.open(renders / file).convert('RGBA')
    sprite = sprite.resize((256, 256), Image.Resampling.LANCZOS)
    canvas.paste(sprite, (round(x), round(y)), sprite)
    return canvas


def frame(pose, index, title, x=220, y=65):
    return compose(f'{pose}-{index % 24:02d}.png', title, x, y)


gesture = json.loads((renders / 'pickup-r2-gesture.json').read_text())
pickup = []
for i, step in enumerate(gesture):
    title = ('側身拎起，前後腿自然錯開' if step['pose'] == 'carried'
             else '放手，輕輕坐回原處' if i >= 72 else '按住拖曳，拎起小黑貓')
    pickup.append(compose(step['file'], title, x=300 + step['x'] * 0.45, y=65 - step['y'] * 0.45))


sequences = {
    '01_點擊回應.gif': [frame('sitting', i, '點一下，牠會回應你') for i in range(8)]
        + [frame('petted', i, '點一下 → 呼嚕～') for i in range(24)]
        + [frame('sitting', i, '回應結束，繼續安靜待著') for i in range(12)],
    '02_拎起放下.gif': pickup,
    '03_洗臉.gif': [frame('grooming', i, '平常照自己的節奏洗洗臉') for i in range(24)],
}
overview = []
overview_duration = []
for name, sequence in sequences.items():
    overview.extend(sequence)
    overview_duration.extend([42 if name == '02_拎起放下.gif' else 83] * len(sequence))
overview.extend(frame('walking', i, '閒置時散步，滑鼠移動不會吸引牠', x=130+i*9) for i in range(24))
overview_duration.extend([83] * 24)
sequences['00_互動總覽.gif'] = overview
receipts = []
for name, images in sequences.items():
    target = output / name
    duration = overview_duration if name == '00_互動總覽.gif' else 42 if name == '02_拎起放下.gif' else 83
    images[0].save(target, save_all=True, append_images=images[1:], duration=duration,
                   loop=0, disposal=2, optimize=False)
    with Image.open(target) as encoded:
        assert encoded.n_frames >= 20
        for index in range(encoded.n_frames):
            encoded.seek(index)
            assert encoded.size == (700, 350)
            encoded.load()
        receipts.append({'file': name, 'frames': encoded.n_frames,
                         'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
(output / 'verification.json').write_text(json.dumps(receipts, ensure_ascii=False, indent=2) + '\n')
frame('carried', 12, 'R2 · 側身拎起').save(output / '04_側身姿勢.png')
print(f'Encoded and decoded {len(receipts)} GIFs from native preview frames: {output}')
