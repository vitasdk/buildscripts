#!/usr/bin/env python3
import argparse
import os
from pathlib import Path
import struct
import subprocess
import tempfile


NOTE = struct.pack('<III8sI', 8, 4, 1, b'VitaSDK\0', 1)


def inspect(path, marked):
    data = path.read_bytes()
    header = struct.unpack_from('<16sHHIIIIIHHHHHH', data)
    assert data[:6] == b'\x7fELF\x01\x01' and header[2] == 40
    phoff, shoff = header[5:7]
    phentsize, phnum, shentsize, shnum, shstrndx = header[9:14]
    sections = [struct.unpack_from('<10I', data, shoff + i * shentsize) for i in range(shnum)]
    strings = sections[shstrndx]
    names = data[strings[4]:strings[4] + strings[5]]
    notes = [s for s in sections if names[s[0]:names.index(0, s[0])] == b'.note.vitasdk']
    assert bool(notes) == marked, f'{path.name}: expected marker={marked}, got {len(notes)} notes'
    for note in notes:
        assert note[1] == 7 and not (note[2] & 2) and note[3] == 0 and note[8] == 4
        assert data[note[4]:note[4] + note[5]] == NOTE, f'{path.name}: incorrect marker payload'
        for i in range(phnum):
            ph = struct.unpack_from('<8I', data, phoff + i * phentsize)
            if ph[0] == 1 and ph[4]:
                assert note[4] + note[5] <= ph[1] or note[4] >= ph[1] + ph[4], \
                    f'{path.name}: marker occupies a loadable segment'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('sdk', type=Path)
    parser.add_argument('--linker-dir', type=Path)
    args = parser.parse_args()
    suffix = '.exe' if os.name == 'nt' else ''
    cc = args.sdk / 'bin' / ('arm-vita-eabi-gcc' + suffix)
    ld = args.sdk / 'bin' / ('arm-vita-eabi-ld' + suffix)
    strip = args.sdk / 'bin' / ('arm-vita-eabi-strip' + suffix)
    compiler = [str(cc)]
    if args.linker_dir:
        compiler.append('-B' + str(args.linker_dir.resolve()) + os.sep)
        ld = args.linker_dir / ('ld' + suffix)
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = root / 'leaf.c'
        source.write_text('int module_start(void) { return 0; }\nint main(void) { return 0; }\n')
        obj = root / 'leaf.o'
        subprocess.run([*compiler, '-c', str(source), '-o', str(obj)], check=True)
        inspect(obj, False)
        partial = root / 'partial.o'
        subprocess.run([str(ld), '-r', str(obj), '-o', str(partial)], check=True)
        inspect(partial, False)
        for name, flags in [
                ('nostdlib', ['-nostdlib']),
                ('gc', ['-nostdlib', '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections']),
                ('lto', ['-nostdlib', '-flto']),
                ('normal', [])]:
            output = root / (name + '.elf')
            subprocess.run([*compiler, *flags, '-Wl,-q,-e,module_start',
                            str(source), '-o', str(output)], check=True)
            inspect(output, True)
            subprocess.run([str(strip), '--strip-debug', str(output)], check=True)
            inspect(output, True)
        direct = root / 'direct.elf'
        subprocess.run([str(ld), '-q', '-e', 'module_start', str(partial), '-o', str(direct)], check=True)
        inspect(direct, True)
    print('VitaSDK ELF marker contract OK')


if __name__ == '__main__':
    main()
