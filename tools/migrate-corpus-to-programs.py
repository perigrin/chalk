# ABOUTME: Migrate mdtest cases from value-fragments to programs whose value is
# ABOUTME: observable via say(): rewrites the source, behavior and ir blocks.
import re, sys

def migrate_source(src):
    """Wrap the final bare expression in say(). Returns (new_src, ok)."""
    body = re.sub(r'^#[^\n]*\n', '', src, count=1)   # drop the "# source" marker
    lines = body.rstrip('\n').split('\n')
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        return None, False
    last = lines[-1].strip()
    # Only the uniform shape: a bare final expression (no trailing ; or }).
    if last.endswith(';') or last.endswith('}'):
        return None, False
    # A source line often holds SEVERAL statements
    #   my $c = 1; if ($c) { print "a" } else { print "b" } 1
    # so wrap only the trailing VALUE expression: scan back to the last
    # top-level `;` or `}` and take what follows. Wrapping the whole line
    # produces `say(my $c = 1; if ...)`, which is not valid perl.
    depth, cut = 0, 0
    for i, ch in enumerate(last):
        if ch in '{([':
            depth += 1
        elif ch in '})]':
            depth -= 1
            if depth == 0:
                cut = i + 1
        elif ch == ';' and depth == 0:
            cut = i + 1
    head, value = last[:cut], last[cut:].strip()
    if not value:
        return None, False
    lines[-1] = (head + ' ' if head else '') + 'say(%s);' % value
    # `say` needs the feature enabled; the harness hoists `use` lines to @head.
    if not any(l.strip().startswith('use 5.42') for l in lines):
        lines.insert(0, 'use 5.42.0;')
    return '# source\n' + '\n'.join(lines) + '\n', True

def migrate_behavior(beh, printed):
    """return: X  ->  stdout: X\\n + return: Bool:1 (say's own value)."""
    out, seen_return = [], False
    for line in beh.rstrip('\n').split('\n'):
        m = re.match(r'^return:\s*(.*)$', line)
        if m:
            val = m.group(1)
            # Strip a type tag: stdout carries the VALUE, not its repr.
            val = re.sub(r'^(?:Int|Num|Str|Bool|Undef):', '', val)
            out.append('stdout: %s%s\\n' % (printed, val))
            out.append('return: Bool:1')
            seen_return = True
            continue
        if line.startswith('stdout:'):
            continue   # folded into the line above
        out.append(line)
    return ('\n'.join(out) + '\n') if seen_return else None

def migrate_ir(ir):
    """Thread the returned value through a Print, and return the Print."""
    lines = ir.rstrip('\n').split('\n')
    ret_i = next((i for i, l in enumerate(lines) if l.startswith('return ')), None)
    if ret_i is None:
        return None
    val = lines[ret_i][len('return '):].strip()
    if not val.startswith('%'):
        return None
    ctrl_i = next((i for i, l in enumerate(lines) if l.startswith('control:')), None)
    new = lines[:ret_i]
    new.append('%nl = Constant("\\n") :Str')
    new.append('%%p  = Print(%s, %%nl)' % val)
    new.append('return %p')
    for l in lines[ret_i + 1:]:
        if l.startswith('control:'):
            continue
        new.append(l)
    return '\n'.join(new) + '\n'

def migrate_file(path):
    text = open(path).read()
    parts = text.split('\n## ')
    out, done, skipped = [parts[0]], 0, []
    for sec in parts[1:]:
        title = sec.split('\n')[0]
        msrc = re.search(r'```perl\n(.*?)```', sec, re.S)
        mbeh = re.search(r'```behavior\n(.*?)```', sec, re.S)
        mir  = re.search(r'```ir\n(.*?)```', sec, re.S)
        if not (msrc and mbeh and mir) or 'L: GAP' in mir.group(1):
            skipped.append((title, 'gap-declared or missing block'))
            out.append(sec); continue
        new_src, ok = migrate_source(msrc.group(1))
        if not ok:
            skipped.append((title, 'source does not end in a bare expression'))
            out.append(sec); continue
        printed = ''
        mstdout = re.search(r'^stdout:\s*(.*)$', mbeh.group(1), re.M)
        if mstdout:
            printed = mstdout.group(1)
        new_beh = migrate_behavior(mbeh.group(1), printed)
        new_ir  = migrate_ir(mir.group(1))
        if new_beh is None or new_ir is None:
            skipped.append((title, 'behavior/ir block not in the uniform shape'))
            out.append(sec); continue
        sec = sec.replace(msrc.group(0), '```perl\n' + new_src + '```', 1)
        sec = sec.replace(mbeh.group(0), '```behavior\n' + new_beh + '```', 1)
        sec = sec.replace(mir.group(0),  '```ir\n' + new_ir + '```', 1)
        out.append(sec); done += 1
    open(path, 'w').write('\n## '.join(out))
    print('%s: migrated %d' % (path, done))
    for t, why in skipped:
        print('    SKIPPED %-52s %s' % (t[:52], why))

for p in sys.argv[1:]:
    migrate_file(p)
