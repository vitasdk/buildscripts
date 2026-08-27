#!/usr/bin/env python3
"""Generate the softfp-world naked ABI shims for the 23 float/double crossings
found by ../artifacts/softfp-abi-audit/scan-float-abi.py (see results.tsv and
PLAN-softfp.md, "Fase 1" / los 23 shims de serie).

A shim translates a single AAPCS-base (softfp) call into the AAPCS-VFP (hard)
call the real Sce* stub expects: move each float/double argument from its
softfp slot (core register or stack, counted together with every other
argument) into its hard-float slot (an S/D register, counted only among the
float/double arguments), and move a float/double return value back from
s0/d0 into r0 or r0:r1. Everything else (pointers, plain integers) already
sits in the same core register on both sides and is left untouched.

Each generated file defines exactly one symbol, named like the real
function, and branches or calls into `__vita_softfp_target_<name>` -- the
real stub, renamed by scripts/patch-softfp-stub-archives.sh so the wrapper
can carry the original name without colliding with it. This script only
emits the wrapper .S files; splicing them into the installed stub archives
is that shell script's job.

Regenerate when scan-float-abi.py reports a different set of user-facing
crossings:

    python3 generate.py <vita-headers>/include

`functions.tsv` (name, header path relative to include/, stub module) is
hand-curated from that report, not derived automatically -- it is small and
its correctness matters more than saving the curation step.
"""

import argparse
import os
import re
import sys

FLOAT_TYPES = {"float", "SceFloat", "SceFloat32", "ScePvfFloat32"}
DOUBLE_TYPES = {"double", "SceDouble", "SceDouble64"}

FUNCTION = re.compile(r"([\w\s\*]+?)\b(\w+)\s*\(([^()]*)\)\s*;")

HEADER = """\
\t.syntax unified
\t.thumb
\t.text
\t.align\t2
\t.global\t{name}
\t.thumb_func
\t.type\t{name}, %function
{name}:
"""


def classify_type(text):
    text = text.strip()
    if "*" in text:
        return "core"
    tokens = text.split()
    if any(token in FLOAT_TYPES for token in tokens):
        return "float"
    if any(token in DOUBLE_TYPES for token in tokens):
        return "double"
    return "core"


def find_signature(header_text, name):
    flat = re.sub(r"\s+", " ", header_text)
    for return_type, found_name, parameters in FUNCTION.findall(flat):
        if found_name != name:
            continue
        params = []
        parameters = parameters.strip()
        if parameters and parameters != "void":
            for parameter in parameters.split(","):
                params.append(classify_type(parameter))
        ret_kind = "void" if return_type.strip() == "void" else classify_type(return_type)
        return ret_kind, params
    raise LookupError(f"declaration of {name} not found")


def softfp_slots(params):
    """Every argument, float or not, consumes one word in declaration order."""
    return list(enumerate(params))


def hard_destinations(params):
    core_idx = 0
    float_idx = 0
    dests = []
    for kind in params:
        if kind == "float":
            dests.append(("vfp", float_idx))
            float_idx += 1
        elif kind == "core":
            dests.append(("core", core_idx))
            core_idx += 1
        else:
            raise NotImplementedError("double/HFA parameters are not handled")
    if core_idx > 4 or float_idx > 16:
        raise NotImplementedError("more core/vfp arguments than fit in registers")
    return dests


def slot_source(slot):
    if slot < 4:
        return ("reg", slot)
    return ("stack", (slot - 4) * 4)


def emit_body(name, target, ret_kind, params):
    dests = hard_destinations(params)
    lines = []

    # Float args first: every vmov reads an *original* softfp register/stack
    # slot, before anything below overwrites r0-r3. Register-sourced floats
    # are read first (they alias r0-r3 directly); stack-sourced floats are
    # loaded through a scratch core register afterwards, since by then their
    # register-sourced siblings have already been consumed.
    scratch_regs = ["r1", "r2", "r3"]
    pending_stack = []
    for slot, kind in softfp_slots(params):
        if kind != "float":
            continue
        dest_idx = dests[slot][1]
        source_kind, source = slot_source(slot)
        if source_kind == "reg":
            lines.append(f"\tvmov\ts{dest_idx}, r{source}")
        else:
            pending_stack.append((dest_idx, source))
    for dest_idx, offset in pending_stack:
        scratch = scratch_regs.pop(0)
        lines.append(f"\tldr\t{scratch}, [sp, #{offset}]")
        lines.append(f"\tvmov\ts{dest_idx}, {scratch}")

    # Core (pointer/integer) args next, in increasing destination-register
    # order -- always safe, since a core argument's source slot number is
    # never lower than its destination register number (interleaved float
    # arguments only ever push a source slot further right).
    core_moves = []
    for slot, kind in softfp_slots(params):
        if kind != "core":
            continue
        dest_idx = dests[slot][1]
        source_kind, source = slot_source(slot)
        if source_kind != "reg":
            raise NotImplementedError("stack-sourced core argument")
        if source != dest_idx:
            core_moves.append((dest_idx, source))
    for dest_idx, source in sorted(core_moves):
        lines.append(f"\tmov\tr{dest_idx}, r{source}")

    if ret_kind == "float":
        lines.insert(0, "\tpush\t{lr}")
        lines.append(f"\tbl\t{target}")
        lines.append("\tvmov\tr0, s0")
        lines.append("\tpop\t{lr}")
        lines.append("\tbx\tlr")
    elif ret_kind == "double":
        lines.insert(0, "\tpush\t{lr}")
        lines.append(f"\tbl\t{target}")
        lines.append("\tvmov\tr0, r1, d0")
        lines.append("\tpop\t{lr}")
        lines.append("\tbx\tlr")
    else:
        lines.append(f"\tb\t{target}")

    return "\n".join(lines) + "\n"


def generate_one(name, header_text, out_dir):
    ret_kind, params = find_signature(header_text, name)
    target = f"__vita_softfp_target_{name}"
    body = emit_body(name, target, ret_kind, params)
    path = os.path.join(out_dir, f"{name}.S")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(HEADER.format(name=name))
        handle.write(body)
        handle.write(f"\t.size\t{name}, . - {name}\n")
    return path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("include_dir", help="vita-headers include/ directory")
    parser.add_argument("--functions", default=os.path.join(
        os.path.dirname(__file__), "functions.tsv"))
    parser.add_argument("--out", default=os.path.join(
        os.path.dirname(__file__), "wrappers"))
    options = parser.parse_args()

    os.makedirs(options.out, exist_ok=True)

    headers = {}
    with open(options.functions, encoding="utf-8") as handle:
        rows = [line.rstrip("\n").split("\t") for line in handle if line.strip()]

    generated = []
    for name, header, _module in rows:
        if header not in headers:
            with open(os.path.join(options.include_dir, header),
                       encoding="utf-8") as handle:
                headers[header] = handle.read()
        generated.append(generate_one(name, headers[header], options.out))

    print(f"generated {len(generated)} wrappers in {options.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
