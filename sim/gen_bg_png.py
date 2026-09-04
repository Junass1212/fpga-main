# 把任意1024x600的PNG转成demo3仿真的背景帧hex
# 用法: python gen_bg_png.py <图片路径>
import sys
from PIL import Image

png = sys.argv[1] if len(sys.argv) > 1 else r'E:/FPGA/lab_hd_3_osd/input.png'
W, H = 1024, 600

img = Image.open(png).convert('RGB')
assert img.size == (W, H), f'尺寸不对: {img.size}, 需要 {W}x{H}'
px = img.load()

buf, blen = 0, 0
lines = []
with open('bg_frame.hex', 'w', newline='\n') as f:
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            buf = (buf << 24) | (r << 16) | (g << 8) | b
            blen += 24
            while blen >= 128:
                blen -= 128
                word = (buf >> blen) & ((1 << 128) - 1)
                buf &= (1 << blen) - 1
                lines.append('%032x' % word)
                if len(lines) >= 4096:
                    f.write('\n'.join(lines) + '\n')
                    lines = []
    assert blen == 0
    if lines:
        f.write('\n'.join(lines) + '\n')

print('bg_frame.hex regenerated from', png)
