# Representation-decision sites for Chalk `Num` and `Int` in the LLVM backend

Measurement only. Nothing under `lib/` was modified. Date: 2026-08-31.
Files inventoried: `lib/Chalk/Target/LLVM/Context.pm` (8930 lines),
`lib/Chalk/Target/LLVM.pm` (1416 lines).

Every classification below cites the line as read.

## The honest count

    grep -c double  Context.pm  95     LLVM.pm  15
    grep -c i64     Context.pm 449     LLVM.pm  55

**The coordinator's "284 sites hardcode a machine type" is inflated by roughly
an order of magnitude.** The measured totals:

| Class | Context.pm | LLVM.pm | Total |
|---|---|---|---|
| (a) REPRESENTATION — `double` chosen because the Chalk type is `Num` | 26 | 8 | **34** |
| (a) REPRESENTATION — `i64` chosen because the Chalk type is `Int` | 11 | 5 | **16** |
| (b) STRUCTURAL `double` — libc/aggregate signature, repr-independent | 5 | 3 | 8 |
| (b) STRUCTURAL `i64` — lengths, capacities, GEP indices, malloc sizes, the `%Slot` payload word | ~430 | ~47 | ~477 |
| (c) comment / doc prose | 64 | 4 | 68 |

**50 representation-deciding sites total** (34 `double` + 16 `i64`), against
~485 structural machine-type uses that are correctly fixed regardless of any
Chalk type. The 284 figure counted structural i64 — GEP indices, `%StrPair.len`
loads, `malloc` sizes, `snprintf` lengths — as if each were a representation
decision. They are not: an array's length is `i64` because that is the
aggregate's own field width, not because anything in it is a Chalk `Int`.

Of the 50, **12 are opcode selections** (section 4) and **38 are type-name
selections** (sections 1–2). Only the 12 are hard.

## 1. (a) REPRESENTATION sites — `double` because the Chalk type is `Num`

Each row: `file:line`, enclosing sub, and what the site would need in order to
*ask* rather than assume. "`_repr_to_llvm_type($repr)` in scope" means the repr
is already a live variable at that line and the call is a one-token swap;
"needs plumbing" means the repr is not currently available there.

### Context.pm — type-name selections

| line | sub | what it emits | what it needs to ask instead |
|---|---|---|---|
| 113 | `new` (field init comment/decl for `_pkg_num_globals`) | comment naming the slot shape | doc only, follows :654 |
| 654 | `render_need_flag_prologue` | `internal global double 0.0` for a Num package scalar | the global's own repr is `Num` by construction of `_pkg_num_globals`; needs `_repr_to_llvm_type('Num')` plus a matching zero-literal chooser (`0.0` vs `0`) |
| 1705 | `_lower_constant` | `fadd double 0.0, $dval` for `Constant(repr=Num)` | `$repr` is in scope (:1694). Both the type name AND the opcode — see §4 |
| 1824 | `_lower_binop_int` | `$fop double $lhs, $rhs` | `$repr` in scope (:1803). Type name interpolated beside an opcode from `%_INT_TO_FLOAT_OP` — see §4 |
| 1849 | `_lower_as_double` | `sitofp i64 $ref to double` | has `$orep` (:1844) for the *source*; needs the DESTINATION repr passed in — the sub's name presumes the answer |
| 1883 | `_lower_divide` | `fdiv double $lhs, $rhs` | `$repr` in scope (:1856) and asserted `Num` at :1865 |
| 2377 | `_unbox_payload_as` | `bitcast i64 $payload to double` | `$repr` is the parameter (:2371); `_repr_to_llvm_type($repr)` is a direct swap. The i64 half is STRUCTURAL (payload word) |
| 2450 | `_emit_coercion` | `sitofp i64 $in to double` | `$from`/`$to` are parameters (:2443); both type names are askable — see §4 for the opcode |
| 2453 | `_emit_coercion` | `fptosi double $in to i64` | same; both ends askable |
| 2462 | `_emit_coercion` | `fcmp une double $in, 0.0` | `$from` = `Num`; the `0.0` literal is a second hidden repr assumption |
| 2476 | `_emit_coercion` | `uitofp i1 $in to double` | `$to` = `Num` in scope. Comment at :2469-2474 already names `%_REPR_LLVM_TYPE` as the authority and then does not call it |
| 2489 | `_emit_coercion` | `my $ty = $to eq 'Int' ? 'i64' : 'double'` | **the closest existing site to the functor**: it already branches on the Chalk type to pick a machine type. It is a two-arm inline copy of `%_REPR_LLVM_TYPE` |
| 2568 | `_emit_coercion` | `call double @chalk_str_to_num(...)` | `$to` = `Num`; but the return type is fixed by the emitted helper (LLVM.pm:129), so changing it means changing the helper too — a coupled pair |
| 2683 | `_ensure_i1` | `fcmp une double $ref, 0.0` | `$repr` is the parameter (:2672) |
| 2727 | `_lower_vardecl` | `fadd double 0.0, 0.0` for uninit Num | `$repr` in scope; needs a repr→zero-literal map beside the type map |
| 2949 | `_lower_assign` | `store double $rhs, double* $nname` | `$rhs_repr` in scope (:2894), asserted `Num` at :2948 |
| 3208 | `_coerce_ref_to_num` | `sitofp i64 $ref to double` | `$repr` is the parameter (:3204); like `_lower_as_double`, the sub name presumes the destination |
| 3217 | `_coerce_ref_to_num` | `call double @chalk_str_to_num(...)` | coupled to the helper as :2568 |
| 3263 | `_lower_icmp_int` | `fcmp $fpred double $lhs_d, $rhs_d` | operand reprs in scope (:3239-3240) but the comparison's numeric type is chosen by `_coerce_ref_to_num`, not here |
| 3454 | `_lower_ternary` | `$branch_type = 'double'` when both arms are Num | `$true_repr`/`$fals_repr` in scope (:3453). A literal two-arm re-implementation of `%_REPR_LLVM_TYPE`, same shape as :2489 |
| 3854 | `_lower_defined_or` | `fadd double 0.0, 0.0` fallback | already has `$llvm_type` from `_repr_to_llvm_type` (:3831) and **string-compares it** to `'double'` at :3852. It asks the table for the type then re-hardcodes the zero |
| 6273 | `_lower_array_read` | `bitcast i64 $raw_pay to double` | `$repr` in scope (:6262); the i64 half is the STRUCTURAL payload word |
| 6612 | `_lower_hash_read` | `bitcast i64 $raw_pay to double` | same as :6273 |
| 6757 | `_box_payload` | `bitcast double $val_ref to i64` | `$repr` is the parameter. Note the sibling at :6868 in `_store_field_payload` **already does this correctly** — it calls `_repr_to_llvm_type($repr)` into `$num_ty` and interpolates that. That line is the pattern the other 25 should copy |
| 8581 | `_lower_stash_access` | `load double, double* $nname` | `$repr` in scope (:8577); pairs with the store at :2949 |
| 1297, 1299 | `_pkg_num_global_name` (doc) | comment asserting the Num slot is a `double` | prose stating the assumption; would need updating with :654 |

Already-correct exemplar (NOT a finding, recorded as the model):

    Context.pm:6867   my $num_ty = _repr_to_llvm_type($repr);
    Context.pm:6868   ...bitcast $num_ty $val_ref to i64...

with the comment at :6862-6866 stating exactly the principle: "The machine type
comes from `%_REPR_LLVM_TYPE` rather than being named here … a second literal at
this site would be a parallel authority that could drift."

### LLVM.pm — type-name selections

| line | sub | what it emits | needs |
|---|---|---|---|
| 217 | `_method_fn_llvm_ret_type` | `return 'double' if $repr eq 'Num'` | **a whole second copy of the functor.** The comment at :205-210 records that this function already drifted from Context's once (Context grew a `Scalar` arm this one lacked). It should delegate to `_repr_to_llvm_type` |
| 713, 714 | `_emit_class_registry_ir` | `call double $parent_fn` / `ret double %r` for an inherited Num method | `$ret_repr` in scope (:701); `$fn_ret` at :700 is ALREADY `_method_fn_llvm_ret_type($ret_repr)` and is then ignored for the body |
| 852 | `_emit_class_registry_ir` | `ret double $body_val` | `$ret_repr` in scope; same as above |
| 962 | `_emit_class_registry_ir` | `ret double $body_val` | same |
| 1289–1291 | `lower_with_elaboration` | `fcmp uno/oeq double` non-finite detection + the `0x7FF0…`/`0xFFF0…` bit patterns | `$result_repr` in scope (:1288). The Inf/NaN bit patterns are IEEE-754-double-specific: this is the most repr-entangled site in either file |
| 1308 | `lower_with_elaboration` | `printf(..., double $result_ref)` | `$result_repr` in scope; the `%g` format at :1173 is the paired half |

## 2. (a) REPRESENTATION sites — `i64` because the Chalk type is `Int`

Only where the i64 holds a Chalk `Int` VALUE. Lengths, capacities, GEP indices,
malloc sizes and `%Slot` payload words are excluded as structural.

| line | sub | what it emits |
|---|---|---|
| Context.pm:629 | `render_need_flag_prologue` | `internal global i64 0` — the Int package-scalar slot |
| Context.pm:1680 | `_lower_constant` | `add i64 0, $val` for `Constant(repr=Int)` |
| Context.pm:1833 | `_lower_binop_int` | `$llvm_op i64 $lhs, $rhs` — the Int arm |
| Context.pm:2458 | `_emit_coercion` | `icmp ne i64 $in, 0` — Int truthiness |
| Context.pm:2489 | `_emit_coercion` | the `'i64'` half of the ternary (also counted in §1) |
| Context.pm:2680 | `_ensure_i1` | `icmp ne i64 $ref, 0` |
| Context.pm:2730 | `_lower_vardecl` | `add i64 0, 0` uninit Int |
| Context.pm:2957 | `_lower_assign` | `store i64 $rhs, i64* $gname` |
| Context.pm:3452 | `_lower_ternary` | `$branch_type = 'i64'` when both arms are Int |
| Context.pm:6856 | `_store_field_payload` | `add i64 0, $val_ref  ; identity: Int->i64` |
| Context.pm:8591 | `_lower_stash_access` | `load i64, i64* $gname` |
| LLVM.pm:214 | `_method_fn_llvm_ret_type` | `return 'i64' if !defined $repr \|\| $repr eq 'Int'` |
| LLVM.pm:722 | `_emit_class_registry_ir` | `ret i64 %r` (inherited Int method) |
| LLVM.pm:884, 981 | `_emit_class_registry_ir` | `ret i64 $body_val` |
| LLVM.pm:1283 | `lower_with_elaboration` | `printf(..., i64 $result_ref)` |

Note the asymmetry: `_lower_constant`'s Int arm at :1680 uses `_emit_entry`
while the Num arm at :1705 uses `_emit`. That is an unrelated placement
difference, not a representation one, but any rework touching both must keep it.

### The `!defined $repr` default at LLVM.pm:214 and Context.pm:3244–3245

    LLVM.pm:214       return 'i64' if !defined $repr || $repr eq 'Int';
    Context.pm:3244   my $lhs_int = !defined $lhs_repr || $lhs_repr eq 'Int';

Both treat *absence of a representation* as Int. That is a third, undeclared
authority: it decides a machine type without a Chalk type existing at all.
`_repr_to_llvm_type` refuses this case loudly (Context.pm:4232 signature default
dies on undef). These two sites contradict that refusal.

## 3. (b) STRUCTURAL — do NOT convert

Recorded so a later pass does not re-litigate them.

**`double`, structural (8):**

- `LLVM.pm:129, 189, 194, 195` — `@chalk_str_to_num`'s own signature and returns.
  Structural *as a helper ABI*, but coupled to :2568/:3217 which call it; changing
  Num's representation means changing this helper's signature in lockstep.
- `LLVM.pm:1175` (comment on the non-finite constants), `Context.pm:734, 779`
  (`declare double @strtod`) — libc's signature. `strtod` returns a C `double`
  regardless of anything Chalk does.
- `Context.pm:2076, 2084` — `snprintf(..., double $input_ref)` in `_emit_to_str`.
  Borderline: the varargs slot must match `%.15g`, which is C's format for a
  double. If Num stopped being a double this whole rendering path changes, but
  the `double` token here is dictated by the printf contract, not by a repr lookup.

**`i64`, structural (~477):** every `getelementptr … i64 0, i32 N`, every
`%Array`/`%Hash` length and capacity load/store, `malloc(i64 $size)`,
`strlen`→i64, `%StrPair.len`, the `%Slot` payload word (`{ i1, i8, i64 }`,
Context.pm:4157 comment), and `snprintf` length arguments. 213 of them match a
purely mechanical `getelementptr|malloc|strlen|snprintf|memcpy|len|cap|idx|
index|size|align` filter; the remainder are the same families under other names.

Also structural and worth naming: `Context.pm:640-642` emits an Int-typed
`i64` *length* global beside a Str package scalar's `i8*` pointer global. The
`i64` there is a length, not a Chalk Int.

**Prose (68):** the T2 design note at Context.pm:4070–4141 is the largest block
and is the specification this inventory serves. It already states the rule the
code violates: "**a `Num` need not be a `double`**" (:4083-4084).

## 4. Opcode selections — the hard 12

These pick an *instruction*, not a type name. Representation-independence here
means dispatching on the repr to a whole instruction family, not interpolating
a string into a fixed mnemonic. Swapping `Num |-> i64` at any of these sites
without changing the opcode produces `fadd i64`, which is invalid IR.

| # | line | sub | opcode chosen | dispatch needed |
|---|---|---|---|---|
| 1 | Context.pm:1705 | `_lower_constant` | `fadd` (as a materialize-immediate idiom) | Int uses `add`, Num uses `fadd`; also the literal must gain a `.0` (:1702) only in the float case |
| 2 | Context.pm:1798 | (module scope) `%_INT_TO_FLOAT_OP` | `add→fadd, sub→fsub, mul→fmul` | **this is the existing seam.** It is a one-way map keyed by nothing but the integer mnemonic; the functor version is keyed by (op, repr) |
| 3 | Context.pm:1824 | `_lower_binop_int` | `$fop` from the table above | `if ($repr eq 'Num')` at :1820 is the branch the functor replaces |
| 4 | Context.pm:1849 | `_lower_as_double` | `sitofp` | the arrow `Int <: Num` maps to `sitofp` only when Num↦double; if Num↦i64 the arrow is the identity and this instruction must not exist |
| 5 | Context.pm:1883 | `_lower_divide` | `fdiv` | Perl `/` is float division semantically; that is a TYPE fact (result is Num), not a representation fact. If Num↦i64 were legal here the op would be `sdiv` and the semantics would break — so this site also encodes a soundness side-condition |
| 6 | Context.pm:2450 | `_emit_coercion` | `sitofp` (Int→Num) | the arrow itself |
| 7 | Context.pm:2453 | `_emit_coercion` | `fptosi` (Num→Int) | the reverse arrow |
| 8 | Context.pm:2462 | `_emit_coercion` | `fcmp une` (Num→Boolean) | Int uses `icmp ne` (:2458); one arrow, two instructions by repr |
| 9 | Context.pm:2476 | `_emit_coercion` | `uitofp` (Boolean→Num) | the comment at :2469-2474 records a live bug from getting exactly this wrong (`zext` produced an i64 that only failed once a real Num merged with it) |
| 10 | Context.pm:2490 | `_emit_coercion` | `$op = $to eq 'Int' ? 'add' : 'fadd'` | the opcode twin of the type ternary at :2489. These two lines are the whole functor in miniature, written twice inline |
| 11 | Context.pm:2683 / 2680 | `_ensure_i1` | `fcmp une` vs `icmp ne` | same pair as #8 |
| 12 | Context.pm:3263 / 3252 | `_lower_icmp_int` | `fcmp $fpred` vs `icmp $pred`, via two separate tables `%FCMP_PREDICATE` (:3185-3196) and `%ICMP_PREDICATE` | **two parallel predicate tables keyed by the same Chalk op.** `NumLt` maps to `olt` in one and `slt` in the other; the choice between tables IS the representation decision |

Also opcode-shaped, listed separately because they are reinterpretations rather
than conversions and would become no-ops under Num↦i64:

- Context.pm:2377, 6273, 6612 — `bitcast i64 → double` on unbox
- Context.pm:6757 — `bitcast double → i64` on box
- Context.pm:6868 — the already-correct `bitcast $num_ty …` (§1 exemplar)
- LLVM.pm:1289-1291 — `fcmp uno`/`fcmp oeq` against IEEE-754 bit patterns

## 5. What a functor would need that does not exist today

`_repr_to_llvm_type` (Context.pm:4232) answers **objects** only. Nothing answers
**arrows**. To close the 50 sites, three things are missing:

1. **A zero/identity literal per repr.** Six sites (`0.0` vs `0`) hardcode it:
   Context.pm:654, 2462, 2683, 2727, 2730, 3854. `_repr_to_llvm_type` cannot
   supply it.
2. **An arrow map** `(from_repr, to_repr) → instruction`, currently spread across
   `_emit_coercion`'s if-chain (:2442-2600), `_lower_as_double` (:1841),
   `_coerce_ref_to_num` (:3203) and `_ensure_i1` (:2671) — four functions
   implementing overlapping subsets of the same relation.
3. **An op map** `(chalk_op, repr) → mnemonic`, currently `%_INT_TO_FLOAT_OP`
   (:1798), `%ICMP_PREDICATE`, `%FCMP_PREDICATE` (:3185) and three inline
   ternaries (:2489, :2490, :3452/3454).

The comment at Context.pm:4078-4081 already states why (2) cannot be derived from
(1): "there is no relation whatsoever between `i64` and `double` … the order
information cannot be PRESERVED; it has to be DISCHARGED, and discharged as
instructions." That is exactly the arrow map.

## 6. The measured miscompile, located

The brief's `Int → Num → Str` lossy composition routes through:

- Context.pm:1824 or :1883 or :2450 — the `sitofp` that makes the value a double
- Context.pm:2043 `_emit_to_str`, arm at :2069-2086 — `%.15g` via `snprintf`

The `%.15g` format is chosen at Context.pm:2065 (`_need_num_fmt`) and defined in
LLVM.pm. It is correct *for a double*. It is the wrong renderer for a Num whose
values are all integral, and there is currently no site at which that question
could be asked — `_emit_to_str` receives `$from` (the repr) but Num has exactly
one rendering.

## Contradictions with the brief

1. **"Only 5 `_emit` lines actually name a repr"** — understated. Counting all
   emit sites that select a machine type *because* of a Chalk repr gives 34
   `double` + 16 `i64` = 50 across both files. The brief's grep for
   `_emit("` with `repr=` matches only lines whose emitted *comment text*
   contains the string `repr=`, which is a comment-formatting convention, not
   a classifier. E.g. Context.pm:2949 (`store double … Num package scalar`) is a
   representation decision with no `repr=` in its comment.

2. **"the ~40 float-instruction sites"** — overstated. Filtering the same grep
   to lines that are neither comments nor `refaddr` noise gives **18**:
   Context.pm 1705, 1798 (the op table itself), 1849, 1866 (a die-message
   naming `fdiv` — arguably prose), 1883, 2450, 2453, 2462, 2476, 2490, 2683,
   2727, 3208, 3263, 3854; LLVM.pm 1289, 1290, 1291. Adding the two sites the
   pattern misses because the mnemonic is interpolated (`$fop` at
   Context.pm:1824) and the `@chalk_str_to_num` calls at :2568 and :3217 gives
   an executable float surface of **21**, not ~40.

   The count also *under*-reports in the other direction: the `bitcast`-based
   Num sites (Context.pm 2377, 6273, 6612, 6757, 6868) are representation
   decisions but are not float instructions, so the brief's grep never saw
   them. "~40 float sites" therefore both over- and under-counts the real
   surface, which is why §1–§2 are organized by decision rather than by
   mnemonic.

3. **"`_lower_binop_int:1818` branches on `if ($repr eq 'Num')`"** — the branch
   is at **:1820**, not :1818. `%_INT_TO_FLOAT_OP` is at **:1798**, matching
   the brief. Minor, but the brief said 1818 and 1798; one is right.

4. **"`%_REPR_LLVM_TYPE` … with only 12 calls to `_repr_to_llvm_type`"** —
   there are **8** call sites, all in Context.pm: 2358, 3705, 3831, 4631, 4778,
   5442, 5488, 6867 (4631 and 4778 are fully-qualified calls from a sibling
   package defined in the same file). LLVM.pm has **zero** — it uses its own
   `_method_fn_llvm_ret_type` instead, which is the drift the comment at
   LLVM.pm:205-210 warns about).

5. **A second, undeclared authority the brief did not mention:**
   `_method_fn_llvm_ret_type` (LLVM.pm:212-224) is a complete parallel copy of
   `%_REPR_LLVM_TYPE` written as an if-chain, and its own comment records that
   it has already drifted once. Any T2 work must collapse these two or the
   drift recurs.

6. **A third authority:** `!defined $repr` defaults to Int at LLVM.pm:214 and
   Context.pm:3244-3245, contradicting `_repr_to_llvm_type`'s explicit refusal
   to answer for an undef repr (Context.pm:4232).
