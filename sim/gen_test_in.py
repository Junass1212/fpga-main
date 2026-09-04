# test-in.jpg -> 摄像头侧RGB像素流hex (edge_detect_96的输入格式)
# 每行一个96-bit beat = 4个RGB888像素, px0在[95:72]高位 (与edge_detect_96的解析一致)
# 1024x600 -> 256 beat/行 x 600行 = 153600行
import sys
from PIL import Image

jpg = sys.argv[1] if len(sys.argv) > 1 else '../test-in.jpg'
W, H = 1024, 600

img = Image.open(jpg).convert('RGB')
if img.size != (W, H):
    print(f'resize {img.size} -> {(W, H)}')
    img = img.resize((W, H), Image.LANCZOS)
px = img.load()

n_beats = 0
with open('test_in_beats.hex', 'w', newline='\n') as f:
    lines = []
    for y in range(H):
        for xb in range(W // 4):
            v = 0
            for i in range(4):
                r, g, b = px[xb*4 + i, y]
                v = (v << 24) | (r << 16) | (g << 8) | b
            lines.append('%024x' % v)
            n_beats += 1
            if len(lines) >= 4096:
                f.write('\n'.join(lines) + '\n')
                lines = []
    if lines:
        f.write('\n'.join(lines) + '\n')

print('test_in_beats.hex done:', n_beats, 'beats (expect 153600)')
