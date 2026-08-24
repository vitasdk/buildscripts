#!/usr/bin/env python3
"""Pacman-compatible version comparison (ported from libalpm's rpmvercmp)."""

import sys


def _rpmvercmp(a, b):
    if a == b:
        return 0
    la, lb = len(a), len(b)
    one = two = 0
    while one < la and two < lb:
        start_one, start_two = one, two
        while one < la and not a[one].isalnum():
            one += 1
        while two < lb and not b[two].isalnum():
            two += 1
        if not (one < la and two < lb):
            break
        # A run of separator characters of different length also decides it.
        if (one - start_one) != (two - start_two):
            return -1 if (one - start_one) < (two - start_two) else 1
        ptr1, ptr2 = one, two
        if a[ptr1].isdigit():
            while ptr1 < la and a[ptr1].isdigit():
                ptr1 += 1
            while ptr2 < lb and b[ptr2].isdigit():
                ptr2 += 1
            isnum = True
        else:
            while ptr1 < la and a[ptr1].isalpha():
                ptr1 += 1
            while ptr2 < lb and b[ptr2].isalpha():
                ptr2 += 1
            isnum = False
        seg1, seg2 = a[one:ptr1], b[two:ptr2]
        if seg1 == "":
            return -1
        if seg2 == "":
            return 1 if isnum else -1
        if isnum:
            seg1 = seg1.lstrip("0")
            seg2 = seg2.lstrip("0")
            if len(seg1) != len(seg2):
                return 1 if len(seg1) > len(seg2) else -1
        if seg1 != seg2:
            return 1 if seg1 > seg2 else -1
        one, two = ptr1, ptr2
    if one >= la and two >= lb:
        return 0
    one_char = a[one] if one < la else ""
    two_char = b[two] if two < lb else ""
    if (one >= la and not two_char.isalpha()) or one_char.isalpha():
        return -1
    return 1


def _parse_evr(version):
    i = 0
    while i < len(version) and version[i].isdigit():
        i += 1
    if i < len(version) and version[i] == ":":
        epoch = version[:i] or "0"
        rest = version[i + 1:]
    else:
        epoch, rest = "0", version
    index = rest.rfind("-")
    if index != -1:
        return epoch, rest[:index], rest[index + 1:]
    return epoch, rest, None


def vercmp(a, b):
    if a == b:
        return 0
    epoch_a, ver_a, rel_a = _parse_evr(a)
    epoch_b, ver_b, rel_b = _parse_evr(b)
    result = _rpmvercmp(epoch_a, epoch_b)
    if result == 0:
        result = _rpmvercmp(ver_a, ver_b)
        if result == 0 and rel_a is not None and rel_b is not None:
            result = _rpmvercmp(rel_a, rel_b)
    return result


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: vercmp.py <version1> <version2>", file=sys.stderr)
        sys.exit(2)
    print(vercmp(sys.argv[1], sys.argv[2]))
