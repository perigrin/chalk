# On-Complete Elimination: Reification Through Multiply

**Issue:** #708
**Date:** 2026-04-12
**Status:** Design validated through pushback + alignment review

## Goal

Remove `on_complete`, `on_scan`, `should_scan`, and `on_skip_optional` from
the semiring interface. All reification work moves into `multiply`. The
semiring interface reduces to Goodman's five operations: `multiply`, `add`,
`is_zero`, `one`, `zero`.

## Core Mechanism

The parser annotates Context objects with metadata (token name, rule name,
alt index, predicted-rule info) before calling `multiply`. Each annotation
produces a Context with a unique `refaddr`, so hash-consing keys in
`_mul_ctx` differ naturally. No special handling needed.

### Information Flow

Currently:
```
on_scan(value, rule_name, alt_idx, pos, matched_text)
on_complete(value, rule_name, alt_idx, pos, origin, on_epoch_commit)
should_scan(value, rule_name, alt_idx, pos, matched_text, is_predicted)
```

After:
```
multiply(value, annotated_scan_context)    # replaces on_scan
multiply(value, annotated_complete_context) # replaces on_complete
# should_scan eliminated: invalid scans produce zero in multiply
# on_skip_optional eliminated: absent optionals = multiply(value, one())
```

The annotated contexts carry all metadata that the old callbacks received:
- `rule` field: rule name (already exists on Context)
- `annotations->{alt_idx}`: alternative index
- `annotations->{predicted}`: predicted-rule set (for TI keyword rejection)
- `annotations->{pos}`: chart position
- `annotations->{origin}`: span start position

### Hash-Consing Safety

SA's `_mul_ctx` keys by `"mul:" . refaddr($left) . ":" . refaddr($right)`.
Because the parser creates a new annotated Context before calling multiply,
the right operand has a different refaddr for each rule completion. Same
multiply tree completing as `Expression` vs `CallExpression` produces
different cache keys, so different results. No risk of caching stale
semantic action results.

### Leo Optimization Compatibility

Leo optimization applies only to Boolean semiring (`supports_leo` returns
true). Boolean's on_complete is identity and its multiply is trivially
associative. Since Boolean remains trivial after this change, Leo chains
continue to work.

## Design Decisions

1. **Epoch GC (`on_epoch_commit`)**: Deferred to a follow-up issue. The
   callback mechanism stays for now; it just flows through multiply instead
   of on_complete.

2. **Keyword rejection (`should_scan`)**: Parser annotates Context with
   predicted-rule set. TI's multiply reads `annotations->{predicted}` and
   returns zero for invalid keyword scans. Parser-internal `predicted_at`
   hashref is snapshotted onto the Context at scan time.

3. **FilterComposite::multiply including TI**: Done in Phase 2 (with on_scan
   removal). FC currently skips TI in multiply; this is removed so TI
   participates in multiply like all other semirings.

4. **on_skip_optional**: Generic `multiply(value, one())`. No special
   placeholder metadata. SA action methods that index children by position
   see a `one()` Context for absent optionals.

5. **set_type_context / current_type_context bridge**: Removed. SA reads
   type annotations directly from `annotations->{type}` on the Context.

## Phases

### Phase 1: Parser Annotates Contexts

Parser creates annotated Contexts in two places:
- **Scan**: annotate with rule_name, alt_idx, matched_text, predicted set
- **Complete**: annotate with rule_name, alt_idx, pos, origin

These annotated Contexts become the right operand of multiply.

### Phase 2: Move on_scan and should_scan into multiply

For each semiring, move on_scan logic into multiply (detecting scan contexts
via annotation). TI's should_scan becomes a zero-return path in TI's
multiply when predicted-rule annotation indicates keyword rejection.

FC::multiply stops skipping TI — all semirings participate in multiply.

### Phase 3: Move on_complete into multiply per semiring

For each semiring, move on_complete logic into multiply (detecting complete
contexts via annotation). SA dispatches actions based on rule annotation.
Structural sets bits based on rule annotation. Precedence assigns levels.
TI runs type computation.

Remove on_complete from Earley parser's Complete step — multiply does it.

### Phase 4: Remove on_skip_optional, clean up FC delegation

Replace on_skip_optional calls with multiply(value, one()). Remove all
eliminated methods from semiring interfaces and FilterComposite delegation.

## Risks

- **Phase 2 regression**: Enabling TI in FC::multiply changes semantics for
  every chart item. Must run full test suite after this change.
- **on_skip_optional metadata loss**: SA placeholder Context with
  `${name}_opt` rule is lost. Action methods using positional child indexing
  need verification.
- **CFG state mutation timing**: SA currently mutates annotations on the
  result of extend() in on_complete. After moving to multiply, ensure CFG
  state flows correctly through the new path.

## Verification

```bash
perl -Ilib t/bootstrap/earley-boolean.t
perl -Ilib t/bootstrap/earley-semantic-integration.t
perl -Ilib t/bootstrap/integration-phase0-grammar.t
perl -Ilib t/bootstrap/integration-phase1-recognition.t
perl -Ilib t/bootstrap/integration-phase2a-ir.t
perl -Ilib t/bootstrap/perl-recognize-phase1.t
perl -Ilib t/bootstrap/perl-recognize-phase2.t
perl -Ilib t/bootstrap/semiring-value-propagation.t
```
