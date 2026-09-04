# 生成demo3仿真的背景帧: 1024x600, 打包成DDR里128bit字的排列
# 打包规则(与video_in写入/ISP的96->128转换一致): 像素流MSB在前拼接, 每128bit一个字
# 1024*600像素 = 115200个128bit字 = bg_frame.hex的115200行
W, H = 1024, 600

def pixel(x, y):
    # 深蓝灰底 + 32px网格线 + 对角渐变, 方便肉眼核对OSD位置
    base = (28, 34, 48)
    grid = (58, 68, 92)
    if x % 32 == 0 or y % 32 == 0:
        r, g, b = grid
    else:
        r, g, b = base
    add = (x + y) // 24
    r = min(255, r + add); g = min(255, g + add); b = min(255, b + add)
    return (r << 16) | (g << 8) | b

buf = 0          # 位缓冲
blen = 0         # 缓冲里的bit数
lines = []
with open('bg_frame.hex', 'w') as f:
    for y in range(H):
        for x in range(W):
            buf = (buf << 24) | pixel(x, y)
            blen += 24
            while blen >= 128:
                blen -= 128
                word = (buf >> blen) & ((1 << 128) - 1)
                buf &= (1 << blen) - 1   # 清掉已消费的高位, 防止缓冲无限增长
                lines.append('%032x' % word)
                if len(lines) >= 4096:
                    f.write('\n'.join(lines) + '\n')
                    lines = []
    assert blen == 0, f'位数不整除: {blen}'
    if lines:
        f.write('\n'.join(lines) + '\n')

print('bg_frame.hex done:', 115200, 'words expected')
