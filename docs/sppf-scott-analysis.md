# SPPF Architecture Analysis: Elizabeth Scott's Algorithm vs Chalk Implementation

**Source**: "SPPF-Style Parsing From Earley Recognisers" by Elizabeth Scott (2008)
**Analyzed**: 2025-11-12
**Purpose**: Validate Chalk's SPPF semiring architecture against canonical algorithm

## Executive Summary

After analyzing Elizabeth Scott's canonical paper on SPPF construction from Earley parsers, **the critical finding is that SEQ nodes do not exist in Scott's algorithm**. Instead, Scott uses **intermediate nodes labeled with grammar rule positions**. This has significant implications for Chalk's current SPPF implementation.

### Critical Questions Answered:

1. **Do SEQ nodes exist in Elizabeth Scott's work?**
   **NO.** Scott's algorithm uses intermediate nodes labeled `(A ::= αx · β, j, i)` showing the rule and dot position, NOT generic "SEQ" markers.

2. **How do other implementations keep intra-parse data?**
   They use **grammar-aware intermediate nodes** that maintain rule context throughout parsing.

3. **When are SPPF nodes created?**
   **During parsing**, with each Earley item carrying an SPPF node reference. Symbol nodes are created when rules complete; intermediate nodes are created for binarization.

---

## Scott's SPPF Node Types

Scott defines three types of SPPF nodes (from Section 4, pages 59-60):

### 1. Symbol Nodes
**Label**: `(B, j, i)` where `B` is a grammar symbol (terminal or non-terminal)

**Represents**: Derivation of substring `aj+1...ai` from symbol `B`

**Example** from Scott's Example 1 (page 57):
```
(S, 0, 2)    ← Symbol node for start symbol S spanning full input
(T, 1, 2)    ← Symbol node for non-terminal T
(a, 0, 1)    ← Symbol node for terminal 'a'
```

### 2. Intermediate Nodes
**Label**: `(A ::= αx · β, j, i)` showing the grammar rule and dot position

**Purpose**: Binarization of rules with more than 2 symbols on RHS

**Example** from Scott's Example 2 (page 61):
```
(S ::= S · S, 0, 2)     ← Intermediate node showing rule S ::= S S with dot after first S
(S ::= S · S, 0, 1)     ← Different intermediate node (different span)
```

**Critical Quote** (page 59):
> "An interior node, u, of the SPPF is either a symbol node labelled (B, j, i) or an intermediate node labelled (B ::= γx · δ, j, i)."

### 3. Packed Nodes
**Purpose**: Represent alternative derivations under the same symbol/intermediate node

**Structure**: Each "family of children" is packed under a dedicated packed node

**Example**: When two different derivations produce the same symbol over the same span, they share the symbol node but have separate packed nodes for each derivation path.

---

## Critical Finding: NO SEQ Nodes

### What Scott Uses Instead

Scott's algorithm achieves cubic binarization through **rule-position-labeled intermediate nodes**, not generic sequence markers.

**From Section 4** (page 59):
> "For an additional node the family will have a child labelled (x, l, i). If γ ≠ ε then the family will have a second child labelled (B ::= γ · xδ, j, l)."

This shows that intermediate nodes are always labeled with:
- The specific grammar rule `B ::= γxδ`
- The dot position showing how much of the RHS has been processed
- The span `[j, i]`

### Why This Matters

**Chalk's current approach** (from `lib/Chalk/ParseForest.pm`):
```perl
method create_sequence_node( $left_node, $right_node ) {
    my $start = $left_node->start_pos();
    my $end = $right_node->end_pos();
    my $seq_node = $self->get_or_create_symbol_node( "SEQ", $start, $end );
    # ...
}
```

This creates nodes labeled `(SEQ, j, i)` with **no grammar context**.

**Scott's approach** would be:
```perl
method create_intermediate_node( $rule, $position, $j, $i ) {
    my $label = "$rule->lhs ::= " . rule_prefix($rule, $position) . " · " . rule_suffix($rule, $position);
    my $node = $self->get_or_create_intermediate_node( $label, $j, $i );
    # ...
}
```

Creating nodes labeled like `(Program ::= SEQ · Statement, 0, 15)` with **full grammar context**.

---

## Node Creation Timeline

### Integrated Parser Approach (Section 5)

Scott's "integrated" algorithm (pages 63-64) creates SPPF nodes **during Earley set construction**.

**Key Architecture** (page 62):
> "In order to construct the SPPF as the Earley sets are built, we record with each Earley item the SPPF node that corresponds to it. Thus Earley items are triples (s, j, w) where s is a non-terminal or an LR(0) item, j is an integer and w is an SPPF node with a label of the form (s, j, l)."

### Creation Points:

1. **Symbol Nodes for Completed Rules** (page 64):
   ```
   if Λ = (D ::= α·, h, w) {
       if w = null {
           if there is no node v ∈ V labelled (D, i, i) create one
           set w = v
           if w does not have family (ε) add one }
   ```

2. **Intermediate Nodes During Scanning/Completion** (page 64):
   ```
   let y = MAKE_NODE(B ::= αai+1 · β, h, i + 1, w, v, V)
   ```

3. **Reuse Existing Nodes When Possible**:
   ```
   if there is no node y ∈ V labelled (s, j, i) create one and add it to V
   ```

### When NOT to Create Nodes

From the `MAKE_NODE` function (page 64):
> "Earley items of the form (A ::= α · β, j) where |α| ≤ 1 do not have associated SPPF nodes, so we use the dummy node null in this case."

This is an optimization: don't create intermediate nodes for rules with 0 or 1 symbols before the dot.

---

## Binarization Strategy

### Cubic Complexity Proof (Section 6, page 65)

**Non-packed nodes**: O(n²)
- Characterized by (LR(0)-item, j, i)
- At most |grammar| × n² such triples

**Packed nodes per non-packed node**: O(n)
- Characterized by pivot point `l` where j ≤ l ≤ i
- At most n choices for `l`

**Total**: O(n³) nodes and edges

### How Rules > 2 Symbols Are Binarized

For rule `A ::= B C D`, Scott creates:
- Parse `B` → get node `(B, j, k)`
- Parse `C` → get node `(C, k, l)`
- Combine → create intermediate `(A ::= B C · D, j, l)` with children `(A ::= B · C D, j, k)` and `(C, k, l)`
- Parse `D` → get node `(D, l, i)`
- Combine → create symbol `(A, j, i)` with children `(A ::= B C · D, j, l)` and `(D, l, i)`

**Critical**: Each intermediate node is labeled with the specific rule and position, maintaining full grammar context.

---

## Scott's Example Analysis

### Example 3 (Section 4, pages 61-62): Hidden Left Recursion and Cycles

**Grammar**:
```
S ::= A T | a T
A ::= a | B A
B ::= ε
T ::= b b b
```

**Input**: `abbb`

**Resulting SPPF Structure** (from page 62, simplified):
```
(S, 0, 4) ← Root symbol node
├─ packed: S ::= A T
│  ├─ (S ::= A · T, 0, 1)  ← Intermediate node with rule context
│  │  ├─ (A, 0, 1)
│  │  │  ├─ packed: A ::= a
│  │  │  │  └─ (a, 0, 1)
│  │  │  └─ packed: A ::= B A
│  │  │     ├─ (A ::= B · A, 0, 0)  ← Intermediate for recursion
│  │  │     │  └─ (B, 0, 0)
│  │  │     │     └─ (ε)
│  │  │     └─ (A, 0, 1) [self-reference creates cycle]
│  │  └─ (T, 1, 4)
│  └─ ...
```

**Notice**:
- Intermediate nodes like `(S ::= A · T, 0, 1)` and `(A ::= B · A, 0, 0)`
- These are labeled with the **specific grammar rule and dot position**
- NO generic "SEQ" nodes appear anywhere

---

## Comparison: Scott vs Chalk

| Aspect | Scott's Algorithm | Chalk's Current Implementation |
|--------|-------------------|--------------------------------|
| **Intermediate Node Labels** | `(A ::= α · β, j, i)` with full rule context | `(SEQ, j, i)` with no grammar info |
| **Node Creation Timing** | During Earley parsing, attached to items | During semiring multiply/on_complete |
| **Grammar Context** | Maintained throughout via rule labels | Lost during multiply, recovered in on_complete |
| **Binarization Mechanism** | Rule-position-labeled intermediate nodes | Generic sequence nodes |
| **Symbol Node Creation** | When rule completes (dot at end) | In on_complete() hook |
| **Intermediate Node Purpose** | Represent partial rule derivations | Represent sequencing (no rule tie) |

---

## Implications for Chalk's SPPF Semiring

### Current Architecture Issues

1. **`create_sequence_node()` in ParseForest.pm creates generic "SEQ" nodes**
   - These have no tie to grammar rules
   - Violates Scott's architecture

2. **`multiply()` in SPPF semiring calls `create_sequence_node()`**
   - Creates SEQ nodes eagerly without rule context
   - When rule completes, `on_complete()` creates LHS symbol node
   - Result: SEQ nodes persist in forest but shouldn't exist

3. **`add()` method prefers grammar symbols over SEQ**
   - This is a workaround for the architectural issue
   - Trying to hide SEQ nodes after they're created

### What Needs to Change

Based on Scott's algorithm, the correct architecture is:

1. **Semiring operations need rule context**
   - `multiply()` should receive current rule and dot position
   - Can then create proper intermediate nodes: `(A ::= αx · β, j, i)`

2. **Eliminate generic SEQ nodes entirely**
   - Replace with rule-labeled intermediate nodes
   - Each intermediate node tied to specific grammar rule

3. **Lazy construction was PARTIALLY correct**
   - Don't create nodes eagerly during multiply ✓
   - BUT when you DO create them, use proper rule labels
   - Need rule information available in semiring element

4. **ParseForest API should support intermediate nodes**
   - `create_intermediate_node(rule, position, j, i)` instead of `create_sequence_node(left, right)`
   - Label format: `"A ::= α · β"` showing rule and dot position

---

## Recommended Architecture Changes

### Phase 1: Add Rule Context to Semiring Elements

Modify `Chalk::Semiring::SPPFElement` to carry rule information:

```perl
class Chalk::Semiring::SPPFElement :isa(Chalk::Element) {
    field $sppf_node :param :reader = undef;
    field @children  :param = ();
    field $forest    :param :reader;
    field $rule      :param :reader = undef;    # NEW: current rule
    field $position  :param :reader = undef;    # NEW: dot position in rule
    field $start_pos :param :reader = undef;
    field $end_pos   :param :reader = undef;
}
```

### Phase 2: Create Intermediate Nodes in multiply()

```perl
method multiply( $other, $swap = undef ) {
    # If we have rule context and RHS length > 2, create intermediate node
    if ($rule && scalar($rule->rhs->@*) > 2) {
        my $new_position = $position + 1;
        my $label = build_intermediate_label($rule, $new_position);
        my $intermediate_node = $forest->create_intermediate_node(
            $label, $start_pos, $other->end_pos
        );
        # Create element with intermediate node
        return Chalk::Semiring::SPPFElement->new(
            sppf_node => $intermediate_node,
            forest => $forest,
            rule => $rule,
            position => $new_position,
            start_pos => $start_pos,
            end_pos => $other->end_pos,
        );
    }
    # For short rules, accumulate children without creating nodes yet
    return Chalk::Semiring::SPPFElement->new(
        children => [$self, $other],
        forest => $forest,
        rule => $rule,
        position => $position,
        start_pos => $start_pos,
        end_pos => $other->end_pos,
    );
}
```

### Phase 3: Update ParseForest to Support Intermediate Nodes

```perl
method create_intermediate_node( $rule_label, $start_pos, $end_pos ) {
    my $key = "$rule_label|$start_pos|$end_pos";
    return $nodes{$key} if exists $nodes{$key};

    my $node = Chalk::ParseForest::IntermediateNode->new(
        rule_label => $rule_label,
        start_pos => $start_pos,
        end_pos => $end_pos,
    );
    $nodes{$key} = $node;
    return $node;
}
```

### Phase 4: Deprecate create_sequence_node()

Remove or deprecate `create_sequence_node()` - it shouldn't exist in Scott's architecture.

---

## References to Scott's Paper

| Topic | Section | Page |
|-------|---------|------|
| SPPF node types defined | Section 4 | 59 |
| Buildtree algorithm | Section 4 | 60 |
| Integrated parser algorithm | Section 5 | 63-64 |
| MAKE_NODE function | Section 5 | 64 |
| Cubic complexity proof | Section 6 | 65 |
| Example with cycles (B ::= ε) | Example 3 | 61-62 |
| Earley's original parser bug | Section 3 | 57-58 |

---

## Conclusion

**SEQ nodes do not exist in Elizabeth Scott's SPPF algorithm.** They are an artifact of Chalk's current implementation that violates the canonical SPPF architecture.

The correct approach is to:
1. Maintain rule context in semiring elements
2. Create **rule-position-labeled intermediate nodes** during parsing
3. Eliminate generic "SEQ" markers entirely

This will align Chalk's SPPF semiring with the proven O(n³) algorithm described in Scott's paper and ensure correct representation of parse forests.

---

## Next Steps

1. ✅ **Document analysis complete** - this document
2. ⏳ Read other papers (Language_Parametric_Module_Management, Baldursson thesis)
3. ⏳ Design rule-context propagation through semiring operations
4. ⏳ Implement intermediate node support in ParseForest
5. ⏳ Refactor SPPF semiring to use rule-labeled intermediate nodes
6. ⏳ Remove SEQ node logic entirely
7. ⏳ Verify all tests pass with correct SPPF architecture
