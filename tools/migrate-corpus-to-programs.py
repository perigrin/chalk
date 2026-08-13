# ABOUTME: Migrate mdtest cases from value-fragments to programs whose value is
# ABOUTME: observable via say(): rewrites the source, behavior and ir blocks.
import re, sys

def _subscript_open(text, i):
    """True when the `{` at text[i] opens a hash SUBSCRIPT, not a block.

    A subscript brace follows a variable, an arrow, or another closing
    bracket: `$h{a}`, `$r->{a}`, `$x{a}{b}`, `$a[0]{k}`. A block brace
    follows a keyword, an operator, or nothing.
    """
    j = i - 1
    while j >= 0 and text[j].isspace():
        j -= 1
    if j < 0:
        return False
    # `$x[0]{k}` / `$x{a}{b}` — chained subscripts. NOT `)`: a paren before a
    # brace is a CONDITION (`if (1) { 2 }`, `while (1) { ... }`), never a
    # subscript chain.
    if text[j] in '}]':
        return True
    # `$r->{a}` — an arrow deref.
    if j >= 1 and text[j - 1:j + 1] == '->':
        return True
    # An identifier directly before `{` is a subscript ONLY when that
    # identifier is a VARIABLE, i.e. it starts with a sigil: `$h{a}` is a
    # subscript, `sub f { ... }` and `if (1) { ... }` are not. Walk back over
    # the identifier and check what introduces it.
    if not (text[j].isalnum() or text[j] == '_'):
        return False
    k = j
    while k >= 0 and (text[k].isalnum() or text[k] == '_'):
        k -= 1
    return k >= 0 and text[k] in '$@%'


def _closes_block(text):
    """True when the trailing `}` of TEXT closes a block rather than a subscript."""
    stack = []
    for i, ch in enumerate(text):
        if ch == '{':
            stack.append('subscript' if _subscript_open(text, i) else 'block')
        elif ch in '([':
            stack.append('paren')
        elif ch in '})]':
            if stack:
                kind = stack.pop()
                # The trailing brace: report what it actually closed.
                if ch == '}' and i == len(text) - 1:
                    return kind == 'block'
    return False


def migrate_source(src):
    """Wrap the final bare expression in say(). Returns (new_src, ok)."""
    body = re.sub(r'^#[^\n]*\n', '', src, count=1)   # drop the "# source" marker
    lines = body.rstrip('\n').split('\n')
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        return None, False
    last = lines[-1].strip()
    # Only the uniform shape: a bare final expression. A trailing `;` means the
    # line is a statement with no value to observe.
    #
    # A trailing `}` is NOT automatically a block close: `$h{a}` and `$r->{a}`
    # end with the brace that closes a SUBSCRIPT, and rejecting them here
    # skipped six hash cases (R3, R5, R7, R10, R19, R20) — they stayed
    # value-fragments, produced no output as programs, and then read as
    # "behaviour divergence, both sides empty". Only a brace whose matching
    # `{` opened a BLOCK ends a statement.
    if last.endswith(';'):
        return None, False
    if last.endswith('}') and _closes_block(last):
        return None, False
    # A source line often holds SEVERAL statements
    #   my $c = 1; if ($c) { print "a" } else { print "b" } 1
    # so wrap only the trailing VALUE expression: scan back to the last
    # top-level `;` or `}` and take what follows. Wrapping the whole line
    # produces `say(my $c = 1; if ...)`, which is not valid perl.
    # A statement boundary is `;` at depth 0, or a `}` that closes a BLOCK.
    # Only `{` opens a block; a closing `)` or `]` ends a sub-expression and
    # must NOT cut, or `($a eq $b) ? 1 : 0` becomes `($a eq $b) say(? 1 : 0)`
    # -- the paren close was treated as the end of a statement.
    # A `}` only ends a statement when it closes a BLOCK — the same rule
    # _closes_block uses. Cutting on a subscript's brace would split
    # `$h{a} + 1` into `$h{a}` and `say(+ 1)`.
    depth, cut, kinds = 0, 0, []
    for i, ch in enumerate(last):
        if ch == '{':
            kinds.append('subscript' if _subscript_open(last, i) else 'block')
            depth += 1
        elif ch in '([':
            kinds.append('paren')
            depth += 1
        elif ch in '})]':
            depth -= 1
            kind = kinds.pop() if kinds else 'paren'
            if depth == 0 and ch == '}' and kind == 'block':
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

    # Print TAKES Str. A non-Str argument is bridged by an explicit
    # Coerce(X -> Str) -- the producer inserts one for a stamped non-Str
    # argument, so an ir block that omits it does not describe the graph the
    # producer builds. son-corpus-wide.t hides this (it runs the real producer,
    # which supplies the Coerce), but every test that BUILDS FROM THE BLOCK gets
    # `GAP: Print of a Int arg` -- which is what most of the red set in
    # t/bootstrap/corpus was.
    #
    # The value's repr is the `:Repr` suffix on its defining line.
    # The repr may be followed by a trailing `# comment`, so strip that before
    # anchoring at end-of-line -- two increment.md blocks were missed by a
    # pattern that did not.
    src_repr = None
    for l in lines[:ret_i]:
        stripped = re.sub(r'\s*#.*$', '', l)
        m = re.match(r'\s*' + re.escape(val) + r'\s*=.*?:(\w+)\s*$', stripped)
        if m:
            src_repr = m.group(1)
    printed = val
    if src_repr and src_repr != 'Str':
        printed = '%co_p'
        new.append('%%co_p = Coerce(%s : %s -> Str) :Str' % (val, src_repr))

    new.append('%nl = Constant("\\n") :Str')
    new.append('%%p  = Print(%s, %%nl)' % printed)
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
