# -*- coding: utf-8 -*-
"""核验 app.asar 内的服务端代码确实包含本轮新增内容。
按 docs §9.9：数据区起点 = (js_start + json_len + 3) // 4 * 4（不是 16 + headerSize，会差 1 字节）。
用法: python _verify_asar.py <app.asar> <文件相对路径> <要找的字符串> ...
"""
import json
import struct
import sys


def read_node(archive, header, rel_path):
    node = header
    for part in rel_path.split('/'):
        files = node.get('files')
        if files is None or part not in files:
            raise KeyError('asar 内找不到路径段: %s' % part)
        node = files[part]
    offset = int(node.get('offset', -1))
    if offset < 0:
        raise KeyError('asar 节点不是文件: %s' % rel_path)
    start = archive['data_start'] + offset
    size = int(node.get('size', 0))
    return archive['raw'][start:start + size]


def open_asar(path):
    with open(path, 'rb') as f:
        data = f.read()
    # asar 头部是 4 个 uint32（整体 pickle / JSON 块 / pickle 负载 / JSON 串长度），
    # JSON 从偏移 16 开始，长度取偏移 12 处的 uint32（比 headerSize 可靠，不会差 1 字节）。
    json_size = struct.unpack('<I', data[12:16])[0]
    header_obj = json.loads(data[16:16 + json_size].decode('utf-8'))
    data_start = (16 + json_size + 3) // 4 * 4
    return {'raw': data, 'header': header_obj, 'data_start': data_start}


def main():
    asar_path = sys.argv[1]
    rel = sys.argv[2]
    needles = sys.argv[3:]
    archive = open_asar(asar_path)
    print('asar: %s' % asar_path)
    print('数据区起点: %d (js_start+len=%d)' % (archive['data_start'], archive['data_start']))
    content = read_node(archive, archive['header'], rel).replace(b'\r\n', b'\n').decode('utf-8', 'replace')
    print('已读取 %s，共 %d 字符' % (rel, len(content)))
    bad = 0
    for n in needles:
        hit = content.count(n)
        print('  %-40s %s (%d 次)' % (n[:40], '✅ 在包内' if hit else '❌ 不在包内', hit))
        if not hit:
            bad += 1
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()