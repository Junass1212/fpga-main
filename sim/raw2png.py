# frames.raw -> 每帧一张PNG (demo3: 1024x600, RGB)
import struct
from PIL import Image

W, H = 1024, 600
FRAME = W * H * 3

data = open('frames.raw', 'rb').read()
n = len(data) // FRAME
print(f'frames.raw: {len(data)} bytes = {n} frames ({len(data) % FRAME} bytes tail)')

for i in range(n):
    fr = data[i*FRAME:(i+1)*FRAME]
    img = Image.frombytes('RGB', (W, H), fr)
    img.save(f'out_frame{i}.png')
    print(f'out_frame{i}.png saved')

# 并排对比图: 背景帧0 vs 帧2 (看计数器变化)
if n >= 3:
    f0 = Image.open('out_frame0.png')
    f2 = Image.open(f'out_frame{n-1}.png')
    combo = Image.new('RGB', (W*2 + 8, H), (40, 40, 40))
    combo.paste(f0, (0, 0))
    combo.paste(f2, (W + 8, 0))
    combo.save('out_compare.png')
    print('out_compare.png saved (首帧 | 末帧)')
