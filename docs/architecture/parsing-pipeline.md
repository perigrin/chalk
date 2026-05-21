<!-- ABOUTME: Architecture of Chalk's five-layer semiring disambiguation pipeline. -->
<!-- ABOUTME: Covers Boolean, TypeInference, Precedence, Structural, SemanticAction, and FilterComposite. -->

# Chalk Semiring Disambiguation Pipeline

This document describes the architecture of the Chalk parsing pipeline: a five-layer semiring stack that progressively narrows an over-generated Earley parse to a single unambiguous derivation, then constructs a Sea of Nodes IR from that derivation.

---

## 1. Overview

Chalk parses Perl using a scanless Earley algorithm over a Perl grammar expressed in BNF. The grammar is intentionally permissive: it accepts constructions that are syntactically ambiguous, and relies on the semiring stack to filter out invalid or lower-priority interpretations during parsing.

The five semirings, applied in order through a `FilterComposite` wrapper, are:

| Index | Semiring         | Responsibility                                              |
|-------|------------------|-------------------------------------------------------------|
| 0     | Boolean          | Recognition: at least one valid parse exists               |
| 1     | Precedence       | Operator precedence and associativity enforcement          |
| 2     | TypeInference    | Semantic knowledge: keywords, builtin signatures, sigils   |
| 3     | Structural       | Block vs. hash disambiguation, call/deref/list tagging     |
| 4     | SemanticAction   | IR node construction via Context comonad                   |

Each semiring operates on its own "slice" of a 5-tuple value that the `FilterComposite` manages. The parse chart stores one 5-tuple per Earley item.

### Ordering Rationale

The canonical order is `[Boolean, Precedence, TypeInference, Structural, SemanticAction]`. Two distinct ordering rules apply, and they are not the same kind of rule:

1. **Filter ↔ filter swaps commute.** The four filtering semirings (Boolean, Precedence, TypeInference, Structural) commute pairwise *with each other* when SemanticAction is last. Disambiguation decisions are gated by zero-propagation and refaddr-based first-wins preference, so any pairwise reordering of the filters produces the same accepted parse set. Audit 5 verified this empirically: across all six permutations of the four filters (with Boolean first and SA last), every test input produced identical parse outcomes. The relative order of the four filters is therefore a performance choice — cheaper checks first so expensive ones short-circuit on already-killed derivations.

2. **SemanticAction-last is structural correctness, not performance.** SA being at index `-1` is enforced by `FilterComposite._sa()` returning `$semirings->[-1]`, and the consequence of violating it is silent total IR loss, not slowdown. SA's `slot_name()` returns `undef`, which causes `_annotation_semirings()` to exclude it; if SA is placed in a non-last slot, its `multiply` is never invoked, no action methods run, and the parse "succeeds" at recognition level while building no IR. Whatever semiring is at `[-1]` is treated as "the SA" by the rest of FilterComposite, regardless of whether it can actually produce IR. There is no error or warning. Audit 5 Finding 2 documents this in detail.

   A related structural rule: TypeInference's behavior is binary position-dependent on the `_sa()` boundary. When TI is at position `[-1]`, its tag-hash output is not stored in `annotations->{type}` on shared Context nodes, and TI's tree-walking signature validation in `_complete_type` becomes a no-op. When TI is in any filter position, that storage happens and signature validation runs. This is not an ordinal dependency — TI's relative position among the filters does not matter — but the last-vs-not-last boundary is structurally significant. Audit 5 Finding 1 documents this; Decision 5 (flow-typing completion) is the architectural resolution.

For full investigation results, see `docs/plans/2026-04-25-audit-5-semiring-contract-reality-findings.md`.

---

## 2. Design Principles

### The Grammar Over-Generates; Semirings Narrow

Chalk's BNF grammar accepts more inputs than are semantically valid Perl. For example:

- `keys %hash` and `keys % hash` both match BinaryExpression, but only the former is a hash operation.
- `if` can match both `QualifiedIdentifier` (a function name) and as the start of an `IfStatement`.
- `{` at the start of an expression can be either the opening of a block or a hash constructor.

The grammar permits all of these. Semirings are responsible for rejecting the interpretations that are not correct.

### Commutativity and the Earley Invariant

Earley parsing merges chart items that span the same input positions via the `add` operation. For disambiguation to be correct, the result must not depend on the order in which alternatives are encountered. All semirings are deterministic under reordering. The four filtering semirings commute pairwise with each other (with SemanticAction last): reordering them within `FilterComposite` does not change which parses are accepted, only how quickly they are rejected. FilterComposite applies a deterministic tie-breaking rule (prefer left) when no semiring expresses a preference.

The "filters commute" claim does *not* extend across the SA boundary: SA must be at `[-1]` for IR to be built, and TI's signature-validation behavior depends on whether TI itself is in last position or in a filter slot (see "Ordering Rationale" above). Filter↔filter commutativity holds; filter↔SA position swaps do not.

### Correctness Over Performance

All design decisions prioritize producing the correct parse over minimizing computation. The semiring stack runs in full for every chart item merge. Optimization passes (Leo optimization, epoch-based chart GC) are applied only where they do not affect the output of any semiring.

---

## 3. The Semiring Interface

Every semiring implements the following protocol. `FilterComposite` calls each method on each component, passing that component's slice of the 5-tuple value.

### Core Algebraic Operations

**`zero()`**
Returns the zero element: the value representing parse failure. Zero propagates through `multiply` and is absorbed by `add`.

**`one()`**
Returns the unit element: the value representing an empty, unconstrained parse. Multiplying any value by one returns that value (identity).

**`is_zero($value)`**
Returns true if `$value` is the zero element. Used to short-circuit multiplication and guide `add`.

**`multiply($left, $right)`**
Combines two values in sequence (corresponding to consecutive symbols in a grammar rule). If either argument is zero, returns zero. Otherwise combines the information from both sides. This is the primary operation for threading state through a rule's body.

**`add($left, $right)`**
Combines two values representing alternative derivations of the same span. Performs disambiguation: returns a single winner (or in some semirings, an arrayref of survivors following the FilterComposite convention). A semiring that cannot distinguish between alternatives returns a value not equal to either input; FilterComposite interprets this as "no preference" and consults the next semiring.

### Parse Event Handling via Annotated Contexts

Parse events (scan, complete, absent optional) are communicated to semirings via annotated `Context` objects passed as the right argument to `multiply`. Semirings inspect `$right->annotations()` to detect the event type:

- **Scan event**: `annotations->{scan} = true`. Focus holds the matched text; `rule_name`, `alt_idx`, and `predicted` (a hashref of rules predicted at this chart position) are also in annotations. Semirings use this to attach type tags, validate operator precedence, and perform keyword rejection.
- **Complete event**: `annotations->{complete} = true`. `rule_name`, `alt_idx`, `pos`, and `origin` are in annotations. Semirings apply rule-completion logic (level assignment, structural tagging, IR node construction). `$right->children->[0]` holds the accumulated child value.
- **Absent optional**: The parser calls `multiply($value, one())` when an optional symbol (`X?`) is skipped. No special annotation is needed; `one()` is the identity element and the result is an unfocused Context node.

This design eliminates separate callback methods (`on_scan`, `should_scan`, `on_complete`, `on_skip_optional`). All semiring logic runs inline during `multiply`, with event type determined by inspection of the right argument's annotations.

### Transitional: slot-based dispatch in FilterComposite

The target signature of `multiply` and `add` is `Context -> Context`: each semiring reads whatever slots it needs from the input Context and returns a new Context with its output written back. Under that design, `FilterComposite` is a pure composition wrapper that threads one Context through each component in order.

Current code is partway there. Component semirings (Precedence, TypeInference, Structural) have narrower signatures — their `multiply` takes a slot value (the hashref stored at `annotations->{their_slot}`) and returns a slot value, not a Context. `FilterComposite` does the Context unwrapping and re-wrapping on each component's behalf, using a `slot_name()` method on each component to know which annotation key to extract and re-stuff. `slot_name()` is not part of the target interface; it's residue from the callback-based pipeline that should go away as component semirings are migrated to true `Context -> Context` signatures. Tracked as X9.

### Lifecycle: `reset_cache()`

Semirings that maintain hash-cons caches (Precedence, TypeInference, SemanticAction, FilterComposite) implement an optional `reset_cache()` method. It clears the cache so it doesn't grow without bound across successive parses and doesn't leak values from a previous parse into the next one.

`FilterComposite::reset_cache()` delegates to each component: `$sr->reset_cache() if $sr->can('reset_cache')`. Boolean and Structural don't implement it — Boolean has no cache; Structural operates on a fixed-size bitfield that doesn't accumulate. The `can` guard keeps the method optional.

Callers (test harnesses, pipeline drivers) should invoke `reset_cache()` on the top-level FilterComposite between distinct parses.

---

## 4. FilterComposite

`FilterComposite` is the outermost semiring presented to the Earley parser. It holds an ordered list of component semirings and manages a 5-tuple value where each element is the value for the corresponding component.

### Shared Context Representation

Each chart item value is a shared `Context` object. All components inspect and annotate the same Context: annotation-layer semirings write to named slots in `annotations` (e.g., `annotations->{precedence}`, `annotations->{structural}`, `annotations->{type}`), and SemanticAction owns the focus field plus the dedicated `scope` and `graph` top-level fields that carry control-flow state.

### Zero Propagation

`is_zero` returns true if the Context's `is_zero` flag is set. Any semiring can kill a derivation unilaterally: a precedence violation, a type mismatch, or a structural conflict all produce the same result — the path is removed from the chart.

`multiply` applies zero propagation per component and short-circuits as soon as any component returns zero. The multiply is atomic: either all components succeed and contribute to a joint result, or the whole product is zero.

### Per-Component Dispatch in `multiply`

All parse event handling (scan, complete, absent optional) flows through `multiply`. `FilterComposite.multiply` calls each annotation-layer semiring's `multiply` in order, passing the full Context objects. Each semiring detects the event type from the right Context's annotations and applies its logic inline. If any component returns zero, `FilterComposite` returns its own zero immediately without calling subsequent components.

After annotation-layer semirings run, the TypeInference tag hash result is threaded to SemanticAction via `set_type_context()` so that action methods can read type annotations via `current_type_context()` during complete events.

### First-Wins Disambiguation in `add`

When two chart items with the same span are merged, `FilterComposite.add()` must select a winner. It proceeds as follows:

1. If either tuple has a zero component, the other tuple wins unconditionally (zero elements are absorbed).
2. `_filter_compare` scans components in priority order. For each component, it first checks whether both inputs are the same reference (via `refaddr` for references, numeric equality for scalars). When both inputs are identical, the component is skipped without calling `add()` — it cannot distinguish between the two. Otherwise, it calls `$semiring->add($li, $ri)` and inspects whether the result equals one of the two inputs (via `refaddr` comparison for references, numeric equality for scalars). A result equal to `$li` but not `$ri` means the component prefers left; a result equal to `$ri` but not `$li` means it prefers right. A result equal to neither means the component produced a new merged value and has no preference.
3. The first component to express a clear preference terminates the search. Subsequent components are not consulted.
4. If no component expresses a preference, left is returned as a deterministic tie-break.

This is the "first-wins ordered priority" model. Earlier semirings have higher priority. Conflicts between semirings have not been observed across the regression suite.

### TypeInference-to-SemanticAction Context Threading

After TypeInference computes its type tag hash during a complete event, `FilterComposite.multiply` wraps it in a Context and passes it to SemanticAction via `set_type_context()` before calling SemanticAction's `multiply`. This bridge allows action methods to read type annotations via `current_type_context()`. The type tag hash is also stored as `annotations->{type}` on the result Context for direct access by tree-walkers.

### Post-Merge Hook

`FilterComposite.add()` calls `on_merge($winner, $loser)` on any component that implements it after the winner is selected. SemanticAction implements `on_merge` to transfer CFG state (`control` token and `scope`) from the loser to the winner when the winner lacks state the loser has. This addresses a specific Earley stale-value issue where `add()` selects an older chart item that predates a CFG state update performed by a semantic action.

---

## 5. Boolean Semiring

`Chalk::Bootstrap::Semiring::Boolean` is the simplest semiring. It answers a single question: does a valid parse exist?

- `zero`: a unique arrayref identity (`$ZERO = []`). Equality is checked via `refaddr` so the zero element cannot be accidentally confused with any other reference.
- `one`: the Perl boolean `true`.
- `multiply`: returns `$ZERO` if either argument is zero; otherwise `true`. Scan and complete events (detected via annotations) are treated identically — both return `true` if value is non-zero.
- `add`: returns `true` if either argument is non-zero; otherwise `$ZERO`.

The Boolean semiring supports Leo optimization (`supports_leo` returns true). Leo's algorithm collapses right-recursive completions into a chain, avoiding O(n^2) behavior. This is safe because multiply is effectively identity for non-zero values and is associative, so skipping intermediate completions does not change the result.

---

## 6. TypeInference Semiring

`Chalk::Bootstrap::Semiring::TypeInference` injects semantic knowledge into the parsing process. It operates on Context objects (from `Chalk::Bootstrap::Context`), which are hash-consed immutable trees.

**Type-system reference.** TypeInference's job is to model Perl's actual type system. The specification of that type system is in `docs/architecture/perl-type-system-practical.md` (intuition, examples, comparison to Moose/Types::Tiny) and `docs/architecture/perl-type-system-formal.md` (operational semantics, observational equivalence, fixed-point treatment of base-type circularity). Any TypeInference design decision should be checkable against those documents. `lib/Chalk/Grammar/Perl/TypeLibrary.pm`'s signatures and type hierarchy are the runtime encoding of that specification; divergence between the papers and TypeLibrary is a finding to surface, not a design choice to make silently. The 2026-04-27 TypeLibrary signature audit (`docs/plans/2026-04-27-typelibrary-signature-audit-findings.md`) is the first systematic check against the spec.

TypeInference is also a producer of type information consumed downstream of the parser. `lib/Chalk/Bootstrap/Perl/Actions.pm:1411` reads TI's `method_return_type` slot via `current_type_context()` to populate `MethodInfo->return_type` on the IR. The data flow is: TI computes `method_return_type` → stores in TI focus hash → FilterComposite threads to SemanticAction via `set_type_context()` → action method reads via `current_type_context()`. TI is therefore not a parser-internal filter only; it is also a typed-data producer for compiler stages, structurally similar to SA's IR production. Decision 5 (flow-typing completion) extends this producer role: TI's output flows through typed nodes rather than `annotations->{type}` slots, dissolving the position-dependence described in §1's Ordering Rationale. See Audit 5 Finding 3 (`docs/plans/2026-04-25-audit-5-semiring-contract-reality-findings.md`) for full evidence.

### Values: Hash-Consed Context Trees

TypeInference values are `Context` objects whose focus is a hashref of type tags. The identity of a Context (its `refaddr`) is used by `FilterComposite._filter_compare` to determine whether two alternatives are equivalent. All Context objects are interned: the same combination of focus tags and child refaddrs always produces the same object.

`zero`: `undef`.
`one`: a singleton Context with focus `{ valid => true }` and no children.
`multiply`: creates a new Context with `undef` focus and both arguments as children. This unfocused multiply node represents a partial derivation that has not yet been completed. Hash-consed by the refaddrs of its children. When the right argument carries `annotations->{scan}=true`, `multiply` returns a type tag hash for the scanned token. When the right argument carries `annotations->{complete}=true`, `multiply` applies type inference for the completed rule.

### Type Tags Attached at Scan Time

The scan branch of `multiply` attaches type information to leaf Contexts based on what was matched:

- `RegexLiteral` scans: `{ type => 'Regex' }`
- `QualifiedIdentifier` scans for known builtins: `{ call_symbol => $name, ident_text => $name }`
- `QualifiedIdentifier` scans for non-builtins: `{ ident_text => $name }`
- `ScalarVariable`, `ArrayVariable`, `HashVariable`: `{ type => 'Scalar' }`, `{ type => 'Array' }`, `{ type => 'Hash' }`
- `NumericLiteral`: `{ type => 'Int' }` for integers, `{ type => 'Num' }` for floats
- `StringLiteral`: `{ type => 'Str' }`
- `Literal` (`undef`/`true`/`false`): `{ type => 'Undef' }`, `{ type => 'Bool' }`
- `BinaryOp` and `UnaryExpression` operators: `{ op_text => $matched_text }`
- `__SUB__`: `{ type => 'CodeRef' }`

Pre-cached singleton Contexts are used for the fixed-tag combinations to avoid object allocation on every scan.

### Type Propagation at Complete Time

The complete branch of `multiply` dispatches to `TypeInferenceActions` (a separate class containing one method per grammar rule) via `can()` followed by `->dispatch()`. Each action method receives the accumulated Context tree for the completed rule and returns a focus hashref for the result. The complete branch then calls `_extend_ctx_with_focus` to create a new focused Context preserving the children from the completed value.

Action methods use tree-walking helpers (`_get_rightmost_type`, `_get_op_text`, `_get_call_symbol`, `_get_item_types`) to extract tags from any depth in the multiply tree. Because the tree is a product of all scans and intermediate completions, tags set at any leaf are reachable from any ancestor.

Key type computations:

- `BinaryExpression`: looks up the operator via `TypeLibrary::get_binary_op($op)` and sets the result type.
- `UnaryExpression`: looks up the operator via `TypeLibrary::get_unary_op($op)`.
- `ExpressionList`: accumulates `item_types` (arrayref of per-position types) and `list_arity`.
- `PostfixDeref` and `Subscript`: set type based on `alt_idx` (array vs. hash vs. scalar dereference).
- `AssignmentExpression`: derives `eval_context` from the LHS variable's sigil type.

### Builtin Signature Validation in `CallExpression`

`CallExpression` completion is handled inline in `TypeInference.pm` rather than dispatched to `TypeInferenceActions`, because it requires coordinating multiple tree-walking results:

1. `_get_call_symbol` retrieves the function name from the accumulated context.
2. `TypeLibrary::get_builtin($name)` fetches the signature: `min_arity`, `arg_types`, `return_type`.
3. `_get_item_types` retrieves the per-position argument types from the ExpressionList context.
4. For each argument position, `TypeLibrary::type_satisfies($actual, $expected)` validates compatibility.
5. If arity is below `min_arity`, or any argument type is incompatible, the complete branch of `multiply` returns `undef` (zero), killing the derivation.

`alt_idx` 2 and 3 correspond to block-first builtins (`map`, `grep`, `sort`), where the block counts as an implicit first argument. The `sig_offset` and `arity` adjustments account for this.

### TypeLibrary: Type Hierarchy and Signatures

`Chalk::Grammar::Perl::TypeLibrary` provides:

- A type hierarchy with 20+ named types organized from `Any` (root) through `Scalar`, `Ref`, `List`, and `Code` branches to leaf types (`Int`, `Str`, `ArrayRef`, etc.).
- O(1) subtype checking via a bitfield representation: each leaf type occupies a unique bit; parent types are the bitwise OR of their descendants.
- `type_satisfies($actual, $required)`: permissive for `undef` actual (unknown type), polymorphic supertypes (`Scalar` satisfies `Str` because a Scalar variable could hold a Str at runtime).
- Builtin signatures for 33 named builtins including array, hash, string, I/O, and control functions.
- Binary operator signatures covering arithmetic, string, comparison, logical, bitwise, regex binding, and range operators.
- Unary operator signatures for `!`, `not`, `-`, `+`, `~`, `\`.

### KeywordTable: Keyword Rejection at Scan Time

`Chalk::Grammar::Perl::KeywordTable` defines three data structures:

- `%KEYWORDS`: all words with dedicated grammar terminals (declarators, control flow, variables, phase blocks, operators, literals, quoting prefixes).
- `%HARD_KEYWORDS`: words that are unconditionally rejected as `QualifiedIdentifier`, regardless of prediction state (`else`, `elsif`). These are never valid as function names.
- `%KEYWORD_RULES`: maps each keyword to the grammar rule(s) that consume it.

The scan branch of `TypeInference.multiply` implements keyword rejection:

1. Only applies to `QualifiedIdentifier` scans (other rule names pass through).
2. Qualified identifiers containing `::` are never keywords; pass through.
3. If the matched text is not in `%KEYWORDS`, pass through.
4. If the matched text is a hard keyword, always reject.
5. Look up `keyword_rules($matched_text)`. For each rule in the list, check whether that rule is predicted at the current chart position using `annotations->{predicted}`. If any consuming rule is predicted, reject the scan (return undef/zero).
6. If no consuming rule is predicted, admit the identifier. This handles the fat-arrow case: `class => "Foo"` inside an expression list, where `ClassBlock` is not predicted.

Additionally, the scan branch rejects `%` as `BinaryOp` when the accumulated context contains a `call_symbol` for `keys`, `values`, or `each`. This prevents `keys %hash` from parsing as `(keys) % (hash)`.

---

## 7. Precedence Semiring

`Chalk::Bootstrap::Semiring::Precedence` enforces Perl's operator precedence and associativity rules. It operates on small hashrefs with fields `valid`, `level`, `assoc`, `is_operator`, and `op` (debug text only). All values are hash-consed via `_intern`.

### The Precedence Table

`Chalk::Grammar::Perl::PrecedenceTable` defines 15 levels, indexed 0 (tightest) to 14 (loosest):

| Level | Associativity | Operators                                        |
|-------|---------------|--------------------------------------------------|
| 0     | right         | `**`                                             |
| 1     | left          | `=~`, `!~`                                       |
| 2     | left          | `*`, `/`, `%`, `x`                               |
| 3     | left          | `+`, `-`, `.`                                    |
| 4     | left          | `<<`, `>>`                                       |
| 5     | nonassoc      | `isa`                                            |
| 6     | chained       | `<`, `>`, `<=`, `>=`, `lt`, `gt`, `le`, `ge`    |
| 7     | nonassoc      | `==`, `!=`, `<=>`, `eq`, `ne`, `cmp`            |
| 8     | left          | `&`                                              |
| 9     | left          | `|`, `^`                                         |
| 10    | left          | `&&`                                             |
| 11    | left          | `||`, `//`                                       |
| 12    | nonassoc      | `..`, `...`                                      |
| 13    | left          | `and`                                            |
| 14    | left          | `or`, `xor`                                      |

Assignment operators (`=`, `+=`, `//=`, etc.) use a synthetic level of 101, right-associative.

### Conceptual Expression Levels

In addition to operator levels, the complete branch of `multiply` assigns conceptual levels to expression-type rules:

| Rule                  | Level | Meaning                                   |
|-----------------------|-------|-------------------------------------------|
| `PostfixExpression`   | -2    | Higher than any binary op                |
| `UnaryExpression`     | -1    | Higher than any binary op                |
| `TernaryExpression`   | 100   | Lower than any binary op                 |
| `AssignmentExpression`| 101   | Lowest; right-associative                |

Negative levels are treated as a distinct domain from binary operator levels. Two negative-level values in `multiply` are passed through without precedence nesting checks.

### Operator Validation at Scan Time

The scan branch of `Precedence.multiply` runs when `$right->annotations()->{scan}` is true. It looks up the operator in `PrecedenceTable`, then checks whether the left operand's accumulated level is compatible:

- If the left operand's level is greater than the operator's level (meaning the left operand has lower precedence than the operator expects), the scan is rejected (`zero` is returned), killing that derivation.
- If compatible, the accumulated value is replaced with a new value carrying the operator's level and setting `is_operator = true`.

This `is_operator` flag marks the value as carrying an operator token, not an expression. The regular `multiply` path uses this flag to distinguish the moment when a `BinaryOp` completion multiplies back into a `BinaryExpression` context from the moment when a right-operand `Expression` is assembled.

Subscript bracket boundary enforcement also occurs at scan time: when `[` or `{` is scanned inside a `Subscript` rule and the accumulated value carries a level >= 0 (indicating a `BinaryExpression` target), the scan is rejected. This prevents `$a->[$i] // $a->[-1]` from parsing as `($a->[$i] // $a)->[-1]`.

### Level Propagation at Complete Time

The complete branch of `Precedence.multiply` runs when `$right->annotations()->{complete}` is true:

- Parenthesized boundaries (`ParenExpr`, `ArrayConstructor`, `HashConstructor`) reset to `one()`, clearing all operator context.
- Expression-type rules (`PostfixExpression`, `UnaryExpression`, `TernaryExpression`, `AssignmentExpression`) are assigned their conceptual level. `PostfixExpression` additionally rejects its value if it carries a level in 0..99, preventing unparenthesized `BinaryExpression` from being a postfix target.
- `BinaryOp`, `AssignOp`, `BinaryExpression`, `Expression`, and postfix rules pass their value through unchanged.
- `Subscript` resets to `one()` for inner levels below 100 (preventing binary operator context from leaking out of subscript brackets), but preserves levels >= 100 so that invalid constructions like `($x = $h){$k}` are still rejected by `PostfixExpression`.
- All other rules return `one()`, clearing operator context.

### `add` Disambiguation

When two Precedence values compete, `add` returns the value with the higher level number (more constraining parent context), on the principle that a tighter constraint prevents more invalid parses downstream. When one value has a level and the other does not, the leveled value wins. When both are unlevel, left is returned. All comparisons use `refaddr` equality because all values are hash-consed.

---

## 8. Structural Semiring

`Chalk::Bootstrap::Semiring::Structural` operates on an 8-bit integer bitfield. It tracks which grammar constructions are present in a derivation and uses this information to select between ambiguous alternatives.

### Bitfield Constants

| Bit | Constant           | Value | Meaning                                         |
|-----|--------------------|-------|-------------------------------------------------|
| 0   | `STRUCT_IS_BLOCK`  | 1     | Completed a `Block` rule                       |
| 1   | `STRUCT_IS_HASH`   | 2     | Completed a `HashConstructor` rule             |
| 2   | `STRUCT_IS_CALL`   | 4     | Completed a `CallExpression` rule              |
| 3   | `STRUCT_IS_LIST`   | 8     | Completed an `ExpressionList` or list alt      |
| 4   | `STRUCT_IS_DEREF`  | 16    | Completed a `PostfixDeref` or `Subscript` rule |
| 5   | `STRUCT_IS_METHOD` | 32    | Completed a `MethodCall` rule                  |
| 6   | `STRUCT_IS_BINOP`  | 64    | Completed a `BinaryExpression` rule            |
| 7   | `STRUCT_IS_VARDECL`| 128   | Completed a `VariableDeclaration` rule         |

`zero`: -1 (outside the valid 0-255 range). `one`: 0 (no bits set). `is_zero`: equality with -1. `multiply`: bitwise OR (with zero propagation). Scan events are transparent pass-throughs.

### Tag Assignment at Complete Time

Each rule completion sets specific bits and selectively inherits bits from the child value:

- `Block`: sets `STRUCT_IS_BLOCK`, preserves `STRUCT_IS_HASH` from children (to distinguish a pure-block from a block containing a hash).
- `HashConstructor`: sets `STRUCT_IS_HASH`.
- `VariableDeclaration`: sets `STRUCT_IS_VARDECL`, preserves `STRUCT_IS_BLOCK`.
- `PostfixDeref`: sets `STRUCT_IS_DEREF`, preserves `STRUCT_IS_BLOCK`, clears `STRUCT_IS_CALL` (a dereference is not a call).
- `Subscript` (all alts): sets `STRUCT_IS_DEREF`, preserves `STRUCT_IS_CALL` and `STRUCT_IS_BLOCK`.
- `CallExpression`: sets `STRUCT_IS_CALL`, preserves `STRUCT_IS_BLOCK`, clears `STRUCT_IS_DEREF` and `STRUCT_IS_METHOD`.
- `MethodCall` with parens (alts 0, 2): sets `STRUCT_IS_METHOD | STRUCT_IS_CALL | child_CALL`.
- `MethodCall` without parens (alts 1, 3): sets `STRUCT_IS_METHOD | child_CALL`.
- `BinaryExpression`: sets `STRUCT_IS_BINOP`, preserves all other bits from children.
- `ExpressionList` alts 1-3 (comma/fat-arrow/trailing-comma): sets `STRUCT_IS_LIST`.
- `ExpressionStatement` alt 1 (`ExpressionList`): sets `STRUCT_IS_LIST`.
- `UseDeclaration` alt 1 (with imports): sets `STRUCT_IS_CALL`.
- `ParenExpr` alt 1 (`ExpressionList`): sets `STRUCT_IS_LIST`.
- Boundary rules (`ParenExpr` alt 0, `ArrayConstructor`): return 0 (clear all bits).

### Disambiguation in `add`

The `add` method applies a priority ordering to resolve structural ambiguities. The rules are applied in order; the first applicable rule determines the winner:

1. Non-list beats list (`is_list` set loses to `is_list` not set).
2. `is_call` beats non-call.
3. When both have `is_call`: non-deref beats deref.
4. When both have `is_call`: non-method beats method.
5. When both have `is_call`: non-binop beats binop.
6. When neither has `is_call`: non-binop beats binop.
7. When neither has `is_call`: non-deref beats deref.
8. `is_hash` beats `is_block` (in expression context, `{...}` is a hash, not a block).
9. When both have `is_hash`: non-block beats block.
10. `is_block` beats neither (when no hash is involved).
11. `is_vardecl` beats non-vardecl.
12. Unresolved: merge all bits via bitwise OR.

These rules encode Perl's disambiguation defaults: a `{` in expression context is a hash; a call that consumes more input is preferred over one that fragments a following expression; `my` as a declarator keyword is preferred over `my` as a bareword function name.

---

## 9. SemanticAction Semiring

`Chalk::Bootstrap::Semiring::SemanticAction` builds the Sea of Nodes IR. It operates on Context objects from `Chalk::Bootstrap::Context`. Control-flow state — the current control token and accumulated variable bindings — lives on Context's top-level `scope` field; the in-flight IR graph (when one is published by an enclosing method/sub action) lives on the `graph` field. The per-parse `Chalk::MOP` and `Chalk::IR::NodeFactory` are likewise carried on top-level `mop` and `factory` fields. See `context-comonad.md` ("Field Threading") and `mop-layer.md`.

### Values and the Context Comonad

SemanticAction values are Context objects. The Context type is defined in `Chalk::Bootstrap::Context` and implements a comonad interface:

- `extract`: returns the focus value (an IR node or `undef` for unfocused multiply nodes).
- `children`: returns the child Contexts.
- `position`: the source position (bookkeeping only, not semantic).
- `rule`: the grammar rule name that produced this Context (set by the complete branch of `multiply`).

`zero`: `undef`. `one`: a singleton Context with `undef` focus, no children, a `scope` field carrying a fresh `Start` node and empty `Scope`, and `mop` and `factory` fields seeded from the per-parse instances set on the semiring via `set_mop()` and `set_factory()`.

`multiply` creates a new Context with `undef` focus and both arguments as children. It propagates `scope`: the right child's scope is preferred (it is later in sequence), but a `Start` control token from the right does not overwrite a more advanced token from the left. Variable bindings from both sides are merged. The `graph` field propagates analogously (right-preferring, left-fallback).

When the right argument carries `annotations->{complete}=true`, `multiply` applies semantic action dispatch for the completed rule (see below).

When an optional symbol (`X?`) is absent, the parser calls `multiply($value, one())`. The `one()` identity produces an unfocused Context node. Action methods that access children by position receive this unfocused node for absent optionals.

### Action Dispatch at Complete Time

The complete branch of `multiply` looks up the action method for `$rule_name` on the `$actions` object via `can()`. If found, the method is called as `$actions->$rule_name($value)`, receiving the accumulated Context tree. The method returns an IR node (or other focus value). A new Context is constructed with that focus and the rule name set.

If no action method is registered, the value passes through unchanged, preserving the Context tree for higher-level actions to consume.

Action methods in `Actions.pm` access scope and control-flow state by reading `$ctx->scope`, `$ctx->graph`, and `$ctx->cfg_state` (a walker that assembles a snapshot from the subtree's scope plus structural annotation keys). They publish updated state by returning a Context whose `scope`/`graph` fields carry the new values; the right-preferring propagation in `multiply` carries those values upward. The MOP and IR factory used to construct nodes inside action methods are reached via `$ctx->mop` and `$ctx->factory` (see `mop-layer.md` and `context-comonad.md`).

### `add` and Disambiguation

SemanticAction's `add` returns an arrayref following the FilterComposite convention:

- If one argument is zero: `[$survivor]`.
- If both are the same object (same refaddr): `[$left]` (identity collapse, no preference).
- If both are different: `[$left, $right]` (genuine ambiguity; FilterComposite picks left as tie-break).

In practice, upstream semirings should eliminate ambiguity before it reaches SemanticAction. When ambiguity reaches SemanticAction and neither argument is preferred, the left-wins tie-break applies. No error is raised: the 1,867-test regression suite has validated that this situation does not produce incorrect parses in the current grammar.

### CFG State and the Stale-Value Problem

The `on_merge` hook addresses a specific Earley engine issue. When `add()` in FilterComposite selects the older of two competing chart items, any CFG state updates that occurred between the time the older item was created and the current position are lost. `on_merge` transfers CFG state from the loser to the winner:

- If the winner lacks CFG state and the loser has it, the loser's state is transferred.
- If both have state, the more advanced control token (non-Start) is preferred and scopes are merged.

---

## 10. Known Issues

### TypeInference Value Propagation: Tags Lost Between Scan and Complete Events

There is a structural limitation in TypeInference's ability to use accumulated type context at scan time.

Tags produced during scan events for a given item are threaded through the multiply tree and are accessible via tree-walking from within the complete branch of `multiply` (which sees the accumulated value for the entire completed rule). However, the scan branch runs for each terminal scan as the rule is being built, before the complete branch has been called. At this point, the accumulated value is an unfocused multiply tree of intermediate scan results.

The issue is that `_extend_ctx_with_focus` (called during completion) replaces the multiply tree with a new focused Context. This focused node is what downstream rules see. But within a rule still being assembled, the multiply tree has not been focused yet. Tree-walkers invoked from the scan branch can search unfocused multiply nodes, but those nodes hold only scan-time tags (type, op_text, ident_text), not the richer completion-level tags (call_symbol propagated through Expression, item_types from ExpressionList).

Practically: when the scan branch for a `BinaryOp` scan tries to check whether the left operand is a `keys`/`values`/`each` call, it can only examine the partially-assembled multiply tree for the current `BinaryExpression`. If the `call_symbol` tag was set by the complete branch for an inner `Atom` or `Expression` and was then folded into a new focused Context by `_extend_ctx_with_focus`, the tree-walker can find it. But if the multiply chain has not yet been focused (e.g., the Expression rule has not yet completed), the tag may not be in any leaf.

In the current implementation, the `keys %hash` case works because `Atom` and `Expression` completions in `TypeInferenceActions` propagate `call_symbol` into the new focused Context's focus hashref, which is reachable by tree-walking. The issue becomes relevant for cases where the blocking context for a semantic rejection depends on a tag that has not yet been promoted through an intermediate completion.

The consequence is that TypeInference cannot reliably reject semantically invalid parses where the invalidity depends on type context that spans multiple rule completions before the point where the scan branch needs to act. For example, rejecting a bareword as a binary operand based on its position in a fully-typed expression would require type information from a higher-level completion that has not yet occurred when the scan branch is processing the bareword.

This limitation does not affect the canonical semiring order, because the four filtering semirings commute pairwise (with SA last): any filter that can kill a derivation eventually does so regardless of its relative position among the filters. The limitation matters for future work that might want TypeInference to prune earlier (reducing downstream semiring work on doomed derivations), which is a performance concern, not a correctness one.

Resolving this limitation would require either (a) a richer tree representation that carries completion-focused nodes at every intermediate step (increasing memory pressure), or (b) a two-pass architecture where TypeInference re-validates completed spans against a finalized type context, similar to the extend-based redesign described in `docs/plans/2026-02-20-typeinference-redesign.md`.

---

## Appendix: Key Source Files

| File | Description |
|------|-------------|
| `lib/Chalk/Bootstrap/Semiring/Boolean.pm` | Boolean recognition semiring |
| `lib/Chalk/Bootstrap/Semiring/Precedence.pm` | Operator precedence semiring |
| `lib/Chalk/Bootstrap/Semiring/TypeInference.pm` | Type-aware disambiguation semiring |
| `lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm` | Per-rule type computation actions |
| `lib/Chalk/Bootstrap/Semiring/Structural.pm` | Structural disambiguation semiring |
| `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` | IR construction semiring |
| `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` | N-ary composition wrapper |
| `lib/Chalk/Grammar/Perl/PrecedenceTable.pm` | 15-level Perl operator precedence table |
| `lib/Chalk/Grammar/Perl/KeywordTable.pm` | Keyword classification and rule mapping |
| `lib/Chalk/Grammar/Perl/TypeLibrary.pm` | Type hierarchy, builtin signatures, operator types |
| `lib/Chalk/Bootstrap/Context.pm` | Comonad context tree implementation |

---

## References

- Goodman, Joshua. "Semiring Parsing." *Computational Linguistics*, 25(4):573-605, 1999. Foundational framework for parameterizing parsers by semirings to obtain different parse products (recognition, counting, Viterbi path, forest). Chalk's FilterComposite extends this with a product semiring that composes five components with priority-ordered disambiguation.
