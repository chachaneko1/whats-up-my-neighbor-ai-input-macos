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


def frame(pose, index, title, x=220, y=65):
    canvas = Image.new('RGB', (700, 350), '#f4f2ed')
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 16), title, font=font, fill='#252526')
    draw.text((24, 318), 'YUI Neko · 原生互動預覽', font=small, fill='#6a6864')
    sprite = Image.open(renders / f'{pose}-{index % 24:02d}.png').convert('RGBA')
    sprite = sprite.resize((256, 256), Image.Resampling.LANCZOS)
    canvas.paste(sprite, (round(x), round(y)), sprite)
    return canvas


sequences = {
    '01_點擊回應.gif': [frame('sitting', i, '點一下，牠會回應你') for i in range(8)]
        + [frame('petted', i, '點一下 → 呼嚕～') for i in range(24)]
        + [frame('sitting', i, '回應結束，繼續安靜待著') for i in range(12)],
    '02_拎起放下.gif': [frame('sitting', i, '按住拖曳，把牠拎起來') for i in range(8)]
        + [frame('carried', i, '拎起時，四隻腳自然垂下',
                 x=220 + math.sin(i / 23 * math.pi) * 100,
                 y=65 - math.sin(i / 23 * math.pi) * 15) for i in range(24)]
        + [frame('sitting', i, '放手，原地坐下') for i in range(16)],
    '03_洗臉.gif': [frame('grooming', i, '平常照自己的節奏洗洗臉') for i in range(24)],
}
overview = []
for sequence in sequences.values():
    overview.extend(sequence)
overview.extend(frame('walking', i, '閒置時散步，滑鼠移動不會吸引牠', x=130+i*9) for i in range(24))
sequences['00_互動總覽.gif'] = overview
receipts = []
for name, images in sequences.items():
    target = output / name
    images[0].save(target, save_all=True, append_images=images[1:], duration=83,
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
print(f'Encoded and decoded {len(receipts)} GIFs from native preview frames: {output}')
