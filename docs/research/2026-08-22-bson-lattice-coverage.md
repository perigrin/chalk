# B::SoN lattice coverage, measured

Date: 2026-08-22
Scope: READ-ONLY audit. No file under `lib/` or `t/` in either repo was modified.

## What this measures

For each member of the type lattice unified in `~/dev/types-paper/2-perl-types-formal.md`,
a minimal perl program constructs a value of that type and prints something derived
from it. Each program is then pushed through the full pipeline and the stage at which
it stops is recorded.

The pipeline mirrors `t/lib/Chalk/CodeGen/Harness/ProgramRunner.pm` — the
file-as-itself contract. Each program is handed to the producer **unmodified**
(no `sub` wrap) and lowered with `program_mode => 1`, so stdout and exit status
are the whole contract.

Stages:

| Stage | Meaning |
|---|---|
| PERL  | perl runs it; stdout + exit status captured as the oracle |
| WIRE  | `perl -I$SON -MO=SoN,json,package=main FILE` emitted decodable JSON (stderr inspected separately) |
| GRAPH | `{methods}{'main::__PROGRAM__'}` exists in the wire, with its ops recorded |
| LOAD  | `Chalk::IR::Serialize::JSON::from_json($json)` returned `($graphs, $mop)` and the entry graph has a Return |
| LOWER | `Chalk::Target::LLVM->lower($ret, program_mode => 1, mop => $mop)` did not die |
| MATCH | `lli` stdout AND exit status both equal perl's |

Environment (verified, not assumed):

- perl `v5.42.0` at `$HOME/.local/share/pvm/versions/5.42.0/bin/perl`
- producer `~/dev/perl5-son`, branch `pu`
- consumer `/home/perigrin/dev/chalk/.claude/worktrees/pu`, branch `phase5-capstone`, HEAD `66ee204b`
- `lli` at `/usr/lib/llvm-15/bin/lli`

Probe: `scratchpad/lattice_probe.pl`. Every row below is command output that was
actually run, and the whole table was run twice with identical results.

## Result table

| Member | PERL | WIRE | GRAPH | LOAD | LOWER | MATCH | Stops at |
|---|---|---|---|---|---|---|---|
| Unknown   | ok | ok | ok      | ok | GAP | –     | `GAP: EntryDef reached LLVM backend with NO representation (undef)` |
| List      | ok | ok | ok      | ok | ok  | MATCH | — |
| Void      | ok | ok | ok      | ok | GAP | –     | `GAP: ArrayRef elem[0] has repr=Undef, which has no i64 payload encoding` |
| Scalar    | ok | ok | ok      | ok | ok  | MATCH | — |
| Undef     | ok | ok | ok      | ok | ok  | MATCH | — |
| Boolean   | ok | ok | ok      | ok | ok  | MATCH | — |
| Str       | ok | ok | ok      | ok | ok  | MATCH | — |
| Num       | ok | ok | ok      | ok | ok  | MATCH | — |
| Int       | ok | ok | ok      | ok | ok  | MATCH | — |
| **VString** | ok | ok | ok | ok | ok | **WRONG** | **perl `3` vs chalk `1`** — see Defect 1 |
| DualVar   | ok | ok | ok      | ok | GAP | –     | `GAP: direct call to 'main::dualvar' has no resolved callee` |
| Ref       | ok | ok | MISSING | –  | –   | –     | producer GAP: `taking a reference to a variable makes it address-taken` |
| Object    | ok | ok | ok      | ok | GAP | –     | `cannot lower op=RefType (not in literal-arithmetic slice)` |
| Regex     | ok | ok | ok      | ok | GAP | –     | `cannot lower op=RefType` |
| ScalarRef | ok | ok | MISSING | –  | –   | –     | producer GAP: address-taken |
| LValueRef | ok | ok | ok      | ok | GAP | –     | `cannot lower op=RefType` |
| ArrayRef  | ok | ok | ok      | ok | GAP | –     | `cannot lower op=Ref` |
| HashRef   | ok | ok | ok      | ok | ok  | MATCH | — |
| CodeRef   | ok | ok | ok      | ok | GAP | –     | `GAP: direct call to 'unknown' has no resolved callee` |
| GlobRef   | ok | ok | ok      | ok | GAP | –     | `cannot lower op=RefType` |
| Array     | ok | ok | ok      | ok | ok  | MATCH | — |
| Hash      | ok | ok | ok      | ok | GAP | –     | `cannot lower op=Call` (`keys`) |
| Code      | ok | ok | ok      | ok | ok  | MATCH | — |
| Glob      | ok | ok | MISSING | –  | –   | –     | producer GAP: `print to an explicit filehandle ... is not lowered` |
| IO        | ok | ok | ok      | ok | GAP | –     | `cannot lower op=RefType` |
| **Format** | ok | ok | ok | ok | ok | **WRONG** | **perl `x` vs chalk `` — see Defect 2** |
| None      | ok | ok | ok      | ok | ok  | MATCH | — (`die` exits 255 in both) |

Tally over the 27 lattice members: **9 MATCH, 13 GAP, 3 producer-MISSING, 2 WRONG.**

Classified by the project's own taxonomy:

- **Cannot translate at all** (no entry graph, named producer GAP): Ref, ScalarRef, Glob — 3
- **Translates, loads, GAPs at lowering** (CORRECT behaviour, the project invariant): Unknown, Void, DualVar, Object, Regex, LValueRef, ArrayRef, CodeRef, GlobRef, Hash, IO — 11
- **Loads but rejected by the loader**: none observed. `from_json` accepted every wire produced.
- **Lowers but produces WRONG output** (the only real defect class): VString, Format — 2

## Defect 1 — VString constants decode to integer 0 (silent miscompile)

`my $v = v1.2.3; print length($v)` prints `3` under perl and `1` under chalk.

The wire shows why. For that program the entry graph is:

```
{"fields":{"const_type":"integer","value":"0"},"id":2,"op":"Constant","stamp":"Int"}
{"id":3,"op":"Length","stamp":"Int"}
```

The vstring's three bytes are gone; the constant is the integer `0`, and
`length(0)` is `1`.

### Root cause

`write`-free and fully localized. A vstring constant is a **PVMG**, confirmed by
the optree:

```
$ perl -MO=Concise,-exec /tmp/vs1.pl
3  <$> const[PVMG "\001\002\003"] s      # my $v = v1.2.3
3  <$> const[PV "abc"] s                 # my $v = "abc"   (for contrast)
```

`SoN::FromOptree::_extract_const` (`lib/SoN/FromOptree.pm:1096-1138`) dispatches
on `isa` in this order:

```perl
if    ($sv->isa('B::IV')) { return ($sv->int_value, ... 'integer') }
elsif ($sv->isa('B::NV')) { ... }
elsif ($sv->isa('B::PV')) { return ($sv->PV, ... 'string') }
```

`B::PVMG` inherits from all three. Measured:

```
B::PVMG isa B::IV   : 1
B::PVMG isa B::NV   : 1
B::PVMG isa B::PV   : 1
@B::PVMG::ISA = B::PVNV
```

So the `B::IV` arm fires first and returns `int_value`, which for a POK-only
PVMG (IOK=0) is `0`. Calling the real function on a real vstring SV confirms it
end to end:

```
vstring  ref=B::PVMG  POK=1 IOK=0 NOK=0 PV_bytes=[1.2.3]
         _extract_const -> value=0 const_type=integer stamp=Int
string   ref=B::PV    POK=1 IOK=0 NOK=0 PV_bytes=[97.98.99]
         _extract_const -> value=abc const_type=string stamp=Str
```

The ordering is the bug: the `B::IV` test is a subtype test, not a flag test, so
it captures every PVMG regardless of whether IOK is set. The later `B::PVIV` /
`B::PVNV` arms *do* consult `SVf_IOK`/`SVf_NOK` correctly — they are simply
unreachable for a PVMG.

### Blast radius — this is a class, not one member

Any POK-only `B::PVMG` constant loses its payload. Measured:

| Construct | SV class | POK | IOK | `_extract_const` result |
|---|---|---|---|---|
| `v1.2.3`             | B::PVMG | 1 | 0 | **`0` / integer** (wrong) |
| a regex-capture copy | B::PVMG | 1 | 0 | **`0` / integer** (wrong) |
| `"abc"`              | B::PV   | 1 | 0 | `abc` / string (right) |
| `dualvar(42,"hello")`| B::PVNV | 1 | 1 | `42` / integer (defensible) |
| `3.5`                | B::NV   | 0 | 1 | `3.5` / number (right) |
| `42`                 | B::IV   | 0 | 1 | `42` / integer (right) |

So VString is the lattice member that surfaced it, but the defect is "POK-only
PVMG constants", which is wider than the lattice row suggests.

### Independent confirmations

Two further probes, both WRONG in the same direction:

- `my $v = v65.66.67; print "$v\n"` — perl `ABC`, chalk `` (empty). The constant
  is `0`, coerced Int→Str, concatenated, printed as nothing meaningful.
- `my $v = v1.2.3; print ord(substr($v,0,1))` — GAPs at lowering (`op=Call`), so
  it does not miscompile, but the wire already carries the wrong `0` constant.

Note one accidental pass: `print length(v1.2.3)` (the vstring as a bare literal
argument) prints `3` correctly, because perl constant-folds `length` at compile
time and the producer never sees the vstring at all. A gate that tested only that
form would report VString as GREEN.

## Defect 2 — `write` is silently discarded (silent construct elision)

```perl
format STDOUT =
@<<<
"x"
.
write;
```

perl prints `x`; chalk prints nothing, exit 0 in both. There is **no GAP, no
stderr diagnostic, and no node**. The entry graph in the wire is:

```
{"id":0,"op":"Start"}
{"fields":{"const_type":"undef","value":null},"id":1,"op":"Constant","stamp":"Undef"}
{"control_in":0,"id":2,"op":"Return"}
```

Producer stderr contains only `/tmp/fmt1.pl syntax OK`.

### Root cause

`write` compiles to a nullary `enterwrite` op:

```
$ perl -MO=Concise,-exec /tmp/fmt2.pl
3  <0> enterwrite v
```

`enterwrite` is **registered** in the op table at
`lib/SoN/FromOptree/OpMap.pm:414`:

```perl
# === Format ===
enterwrite  => [0, undef,        0, 0],
leavewrite  => [1, undef,        1, 0],
formline    => ['mark', 'Call',  1, 0],
```

The entry format is `[pop_count, node_type, push_count, flags]`. For `enterwrite`
the node_type is `undef` and the flags are `0` — notably **not** `SKIP`.

That combination is what makes the elision silent. In `FromOptree::_step`
(`lib/SoN/FromOptree.pm:2615-2630`):

- `$opmap->is_skip('enterwrite')` is false (flags=0), so it falls past the
  bookkeeping shortcut at line 1621
- `$opmap->is_known('enterwrite')` is **true**, so the generic OpMap branch at
  line 2615 is entered
- `pop_count` is 0 → no inputs collected
- `defined $node_type` is **false** → the `make(...)` at line 2630 is skipped
  entirely, so no node is created
- the branch returns `'handled'`

Because the signal is `handled`, the unknown-op guard in the caller —

```perl
# lib/SoN/FromOptree.pm:873-875
# Unknown op - skip with warning
warn "SoN::FromOptree: unknown op '$name', skipping\n";
```

— is **unreachable** for `enterwrite`. A registered-but-nodeless entry is
indistinguishable from a genuine no-op to every downstream check.

Contrast the `SKIP`-flagged entries (`null`, `enter`, `nextstate`, `pushmark`):
those are `undef` node_type *and* SKIP, and they really are semantically empty.
`enterwrite` is a side-effecting op wearing the same costume.

### Blast radius — narrow, and that is the good news

I checked whether unknown side-effecting ops generally vanish. They do not:

| Construct | Ops in wire | Producer stderr |
|---|---|---|
| `write`     | `Constant,Return,Start` (op gone) | *(none)* |
| `warn "w"`  | `Call,Constant,Print,Return,Start` | none |
| `chdir "/tmp"` | `Call,...` | none |
| `sleep 0`   | `Call,...` | none |
| `syswrite(STDOUT,...)` | `Call,...` | none |
| `printf(...)` | `Call,...` | none |
| `local $g = 2` | *(no graph)* | loud producer GAP |

Every other side-effecting builtin becomes a `Call` node (which then GAPs
honestly at lowering) or produces a loud GAP. Only the Format family elides.
`leavewrite => [1, undef, 1, 0]` has the same shape and is presumably the same
hazard, though I did not construct a program that reaches it separately.

### Independent confirmation

```perl
my $n = 0;
format STDOUT =
@<<<<
"hi"
.
write;
print "after\n";
```

perl: `hi\nafter`. chalk: `after`. The surrounding `print` lowers and runs
correctly, so the compiled program looks healthy while one statement has
silently disappeared. This is the worst shape of this defect class: the
divergence is a missing line in the middle of otherwise-correct output.

## Secondary observations

These are not defects, but they matter for a gate design.

**The lattice's arity members are under-probed by any value-based table.**
`Void` in my probe (`sub n { return } my @l = n()`) GAPs on
`ArrayRef elem[0] has repr=Undef`, which is a statement about the empty-list
representation, not about Void as such. Appendix B already separates the arity
coercions (`⇓^List` / `⇓^Scalar`) precisely because they take an expression, not
a value; a gate built from this table should carry that split through.

**`Unknown` is not constructible as a value**, only as a join. My probe forced it
with `@ARGV ? "a" : 1`, and it GAPs at `EntryDef reached LLVM backend with NO
representation (undef)`. That GAP names TypeInference, which is the right place,
but it means "Unknown" as a gate row is really testing join-of-Str-and-Int.

**`RefType` is the single largest GAP bucket** — 5 of the 13 lowering GAPs
(Object, Regex, LValueRef, GlobRef, IO) stop on the identical message
`cannot lower op=RefType (not in literal-arithmetic slice)`. Those five members
would move together on one backend change. That is the highest-leverage single
row group in this table.

**Probe artifact worth recording.** My first run had `Glob` as
`my $v = *STDOUT; print "glob\n"` — which never uses `$v` and therefore reported
MATCH. Corrected to `print {$v} "glob\n"`, it GAPs honestly on explicit-filehandle
print. A lattice gate must ensure each case's output actually *depends* on the
constructed value, or it will manufacture false GREENs exactly like this one.

Relatedly, an `undef` probed via `svref_2object(\my $u)` returns a `B::NULL` with
a nonzero address and takes `_extract_const`'s fallback arm
(`stamp=Unknown, const_type=string`). That is an artifact of probing the function
out of context — a real `const[undef]` op reaches the `unless defined $sv && $$sv`
guard at line 1107 and yields `Undef` correctly, and the Undef lattice member does
MATCH end to end. Not a finding.

## COULD NOT CONFIRM

- Whether `leavewrite` elides independently of `enterwrite`. Both are in the
  Format block with `undef` node_type and no SKIP flag, and the reasoning above
  applies identically, but I did not construct a program that exercises
  `leavewrite` on its own.
- Whether any POK-only PVMG constant other than vstrings and regex-capture copies
  reaches a `const` op in practice. I measured the misdecode on the SV directly
  for both; I did not enumerate every perl construct that folds to a PVMG const.
- Whether the loader rejects any node type. No wire produced in this sweep
  contained a node `from_json` refused, so the "loads but rejected" category is
  untested rather than empty.

## Reproduction

```
perl /path/to/scratchpad/lattice_probe.pl        # the full table
perl /path/to/scratchpad/extract_const_direct.pl # Defect 1, on real SVs
perl /path/to/scratchpad/pvmg_blast.pl           # Defect 1 blast radius
```

Probes live in this session's scratchpad; they are throwaway measurement scripts,
not tests. If the coercion-table gate is built, the two defects above are its
first two red rows.
