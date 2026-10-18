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
    sprite = sprite.resize((312, 288), Image.Resampling.LANCZOS)
    canvas.paste(sprite, (round(x), round(y)), sprite)
    return canvas


def frame(pose, index, title, x=220, y=65):
    return compose(f'{pose}-{index % 24:02d}.png', title, x, y)


gesture = json.loads((renders / 'pickup-gemini-gesture.json').read_text())
pickup = []
for i, step in enumerate(gesture):
    title = ('拎起：肩膀先起，身體與腳跟上' if step['pose'] == 'carried'
             else '放手，輕輕坐回原處' if i >= 180 else '按住拖曳，拎起小黑貓')
    x, y = 300 + step['x'] * 0.45, 65 - step['y'] * 0.45
    picture = compose(step['file'], title, x=x, y=y)
    if step['pressed']:
        # An illustrative pointer at the fixture's fixed grip offset. The cat
        # pixels are still rendered by the same native view used by the App.
        draw = ImageDraw.Draw(picture)
        cx, cy = round(x + 156), round(y + 96)
        shape = [(cx, cy), (cx + 3, cy + 22), (cx + 8, cy + 16),
                 (cx + 13, cy + 24), (cx + 17, cy + 21), (cx + 12, cy + 14), (cx + 20, cy + 13)]
        draw.polygon(shape, fill='#fafaf9', outline='#252526', width=2)
    ImageDraw.Draw(picture).text((477, 318), '模型動作・游標示意', font=small, fill='#6a6864')
    pickup.append(picture)


sequences = {
    '01_點擊回應.gif': [frame('sitting', i, '點一下，牠會回應你') for i in range(8)]
        + [frame('petted', i, '點一下 → 呼嚕～') for i in range(24)]
        + [frame('sitting', i, '回應結束，繼續安靜待著') for i in range(12)],
    '02_拎起放下.gif': pickup,
    '02b_動作慢看.gif': pickup,
    '03_洗臉.gif': [frame('grooming', i, '平常照自己的節奏洗洗臉') for i in range(24)],
}
overview = []
overview_duration = []
for name, sequence in sequences.items():
    if name == '02b_動作慢看.gif': continue
    overview.extend(sequence)
    overview_duration.extend(([20, 20, 10] * 80) if name == '02_拎起放下.gif' else [83] * len(sequence))
overview.extend(frame('walking', i, '閒置時散步，滑鼠移動不會吸引牠', x=130+i*9) for i in range(24))
overview_duration.extend([83] * 24)
sequences['00_互動總覽.gif'] = overview
receipts = []
for name, images in sequences.items():
    target = output / name
    duration = overview_duration if name == '00_互動總覽.gif' else ([30, 40, 30] * 80) if name == '02b_動作慢看.gif' else ([20, 20, 10] * 80) if name == '02_拎起放下.gif' else 83
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
frame('carried', 12, 'Gemini · 補間懸空').save(output / '04_側身姿勢.png')
print(f'Encoded and decoded {len(receipts)} GIFs from native preview frames: {output}')
