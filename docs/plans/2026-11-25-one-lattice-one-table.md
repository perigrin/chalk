# One lattice, one operator table

2026-11-25. A plan, not yet built. This file is the same text in B::SoN and in
chalk.

## The goal

B::SoN and chalk should share one type lattice and one operator result table.
Two rules hold:

- B::SoN stands alone. It never loads a Chalk module.
- chalk's lib loads only Chalk modules and pragmas.

So neither side can `use` the other's module. What they can share is a data
file that both read.

## Where things stand

| Fact | B::SoN | chalk |
|---|---|---|
| lattice | `SoN::IR::Stamp` `%PARENTS` (a list of parents per type) | `TypeLibrary` `%PARENT` (one parent per type) |
| Maybe[T] | rules in `_below` / `join` / `meet` | rules in `is_subtype` / `join_types` / `meet_types` |
| operators | `B::SoN::TypeLibrary` `%SIGNATURES`, keyed by IR node | `%BINARY_OP_SIGNATURES` / `%UNARY_OP_SIGNATURES`, keyed by source spelling |
| result rule | `%RESULT_IS_JOIN` and `result_for` (join, capped) | the fixed `result`; `TypeInferenceActions` adds the unary `+`/`-` rules |
| builtins | `%BUILTIN_SIGNATURES`, plus a copy of pvm's `CORE.tpm` | `%BUILTIN_SIGNATURES` (arity, forms, return type) |

Four tests check that the two copies agree, two in each repo:

- `t/lattice-agrees-with-chalk.t` and `t/bootstrap/lattice-agrees-with-b-son.t`
  compare the type names, the parents, and `is_subtype`/`join`/`meet` on every
  ordered pair. The pairs include every Maybe and None and Unknown.
- `t/operator-table-agrees-with-chalk.t` and
  `t/bootstrap/operator-table-agrees-with-b-son.t` compare each operator's
  operand and result types. Each one holds a source-to-node map and a list of
  disagreements held by name.

These tests catch drift. They do not stop it: each new fact is still written
twice, and the maps in the tests are copies too.

## The proposal: one data file

### What goes in the file

One file, `types.tpm`, in the same line-oriented style as `CORE.tpm`. It
holds:

```
# lattice: a type and its parent; the roots have none
type Unknown
type None            bottom
type List    < Unknown
type Scalar  < List
type Int     < Num
...
# operators: IR node, source spellings with arity, operands, result, rule
op Add       +/2               Num Num -> Num      join
op Negate    -/1               Scalar  -> Scalar   join-numeric
op NumCmp    <=>/2             Num Num -> Int
op And       &&/2 and/2        - -     -> Unknown  join
op Length    length/1          Str     -> Int
```

- A `-` operand means the op requires nothing there. Today B::SoN writes that
  as an empty list and chalk writes it as `List`.
- The rule column is what `%RESULT_IS_JOIN` and the Negate special case say
  today. With it in the file, chalk's type inference can apply the same rule
  instead of its own hand-written arms.
- Maybe[T] stays a rule in code on both sides, as it is now. It is a type
  constructor, not an edge, so it has no line in the file.
- Facts that belong to one side stay in that side's code: chalk's
  `min_arity`/`max_arity`/`forms`, and B::SoN's `%NODE_OPERAND_TYPE`.

### Who owns it

B::SoN owns the file. The IR node names and the stamps are the wire's
vocabulary, and B::SoN produces the wire. B::SoN keeps the file next to
`CORE.tpm` as `lib/B/SoN/types.tpm`.

chalk keeps a byte-identical copy at `lib/Chalk/Grammar/Perl/types.tpm`. It is
a data file, not a module, so chalk's lib still loads only Chalk modules. Both
sides find their own copy the same way `core_tpm_path` does: next to the
module that reads it.

The other candidate owner is pvm, which owns `CORE.tpm` and the formal paper
behind the lattice. If the lattice moves upstream there, both repos copy from
pvm, and the hash check below stays the same.

### Keeping the copies identical

- Both suites hold the file's SHA-256 as a constant. A test in each repo
  (B::SoN's `t/types-tpm-hash.t`, chalk's `t/bootstrap/types-tpm-hash.t`)
  hashes its own copy and compares it with the constant. This runs with no
  other repo present.
- When the other repo is present (`SON_CHALK`, `PERL5_SON_LIB`), the same test
  also compares the two copies byte for byte. A copy that drifts fails in
  both suites.
- To change the file: edit B::SoN's copy and update its hash constant. Copy
  the file into chalk and update chalk's constant in a matching commit. The
  commit message in each repo names the other repo's commit.

## Steps

1. **Settle the held disagreements.** The operator tests hold six by name:
   - `=~`/`!~`: B::SoN keeps the pattern as an attribute, while chalk types
     the right operand as Regex. perl accepts a string there.
   - `defined`, `exists`, `delete`, `ref`: chalk types one Scalar operand,
     while B::SoN's node requires nothing (or takes a container and a key).

   The file cannot hold two answers for one operator, so each of these needs
   one answer first.
2. **Write `types.tpm` from today's tables.** The lattice part already agrees
   on every pair. Add a hash test in each repo.
3. **Lattice from the file.** `SoN::IR::Stamp` builds `%PARENTS` from the
   file, and `TypeLibrary` builds `%PARENT` from it. Keep the lattice-agreement
   tests: they now check that both readers read the file the same way.
4. **Operators from the file.** B::SoN builds `%SIGNATURES` and
   `%RESULT_IS_JOIN` from it. chalk builds its binary and unary tables from the
   spellings column. chalk's `%IR_OP_SOURCE_NAME` and `%IR_OP_OBSERVED_NAME`
   also come from that column.
   - Do this step on its own and run chalk's corpus gate. Publishing an
     operand requirement can mint coercions. The arithmetic family once took
     the gate from 224 to 184
     (docs/plans/2026-09-04-publishing-the-arithmetic-family-fails.md), so
     which ops are published must stay a separate choice from what the file
     says.
5. **Drop the maps in the tests.** With the spellings in the file, the
   operator tests no longer need their own source-to-node maps.
6. **Builtins last.** Fold chalk's builtin return types into the file, next to
   B::SoN's `CORE.tpm` and its measured rows. This is a larger merge: the two
   builtin tables differ widely in coverage today.

## Out of scope here

- `..` with string operands (`'a'..'e'`). Both tables say Int operands; perl
  also takes strings.
- Unary `+`. Both tables say Num; perl returns the operand unchanged, as
  chalk's type inference already knows.
- `=~` with `/g` in list context. Both tables say Boolean; B::SoN stamps such
  a match List.

The agreement tests cannot see these, because both sides agree. They are
recorded here so the file does not copy them in unnoticed.
