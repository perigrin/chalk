# Leo Items Implementation Guide

## Overview

Leo items are an optimization technique for Earley parsers that achieves linear time parsing O(n) for right-recursive grammars, compared to the standard O(n³) complexity. This document outlines how to add Leo item support to the Onyx parser to solve performance issues with rules like `CharSeq -> Char CharSeq`.

## The Problem

Our current parser has a quadratic performance problem with right-recursive rules:

```perl
# Grammar rules causing the problem:
CharSeq -> Char CharSeq  # Right recursion
CharSeq -> Char          # Base case
```

For input like `"hello"` (5 characters), the standard Earley parser creates:
- **Position 0**: `CharSeq -> • Char CharSeq`
- **Position 1**: `CharSeq -> Char • CharSeq` (waiting for CharSeq)
- **Position 2**: `CharSeq -> Char • CharSeq` (another one waiting)  
- **Position 3**: `CharSeq -> Char • CharSeq` (another one waiting)
- **Position 4**: `CharSeq -> Char • CharSeq` (another one waiting)
- **Position 5**: `CharSeq -> Char •` (base case completes)

**Result**: O(n²) items created, O(n²) completion work for n-character strings.

## How Leo Items Solve This

Leo items recognize right-recursive patterns and create a **single Leo item** to represent the entire recursive chain, then jump directly to the chain top during completion instead of walking through intermediate items.

**Performance improvement**:
- **Before**: O(n²) items, O(n) completion steps per level
- **After**: O(n) items, O(1) completion per recursive step

## Implementation Plan

### 1. Leo Item Detection Logic

Add method to identify Leo-eligible items:

```perl
method is_leo_eligible($item) {
    my $rule = $item->rule;
    my @rhs = $rule->rhs->@*;
    
    # Must be right-recursive: A -> α A β where β =>* ε
    # Find if LHS appears in RHS and all symbols after it are nullable
    for my $i (0 .. $#rhs) {
        if ($rhs[$i] eq $rule->lhs) {
            # Check if everything after position $i is nullable
            my $all_nullable = 1;
            for my $j ($i + 1 .. $#rhs) {
                unless ($self->is_nullable($rhs[$j])) {
                    $all_nullable = 0;
                    last;
                }
            }
            return 1 if $all_nullable;
        }
    }
    return 0;
}
```

### 2. Extended EarleyItem Class

Add Leo support fields to EarleyItem:

```perl
class EarleyItem {
    field $rule :param :reader;
    field $dot_pos :param :reader = 0;
    field $start_pos :param :reader = 0;
    field $current_pos :param :reader :writer = 0;
    field $matched_text :param :reader :writer = "";
    field $semantic_value :param :reader = undef;
    field $is_leo_item :param :reader = 0;           # NEW: Leo item flag
    field $leo_base_item :param :reader = undef;     # NEW: Points to base item
    field $transition_symbol :param :reader = undef; # NEW: What symbol transitions here

    method is_leo_completion_item() {
        # Leo completion items are complete items that can trigger Leo jumps
        return $self->is_complete && $is_leo_item;
    }

    method create_leo_item($base_item, $symbol) {
        # Create a Leo item representing a right-recursive chain
        return EarleyItem->new(
            rule => $base_item->rule,
            dot_pos => $base_item->rule->rhs_length, # Dot at end
            start_pos => $base_item->start_pos,
            current_pos => $self->current_pos,
            is_leo_item => 1,
            leo_base_item => $base_item,
            transition_symbol => $symbol
        );
    }
}
```

### 3. Leo Item Management in Parser

Add Leo tracking to ScanlessEarleyParser:

```perl
class ScanlessEarleyParser {
    field @grammar_rules;
    field $ir_graph = ThreadedSeaOfNodes->new();
    field @chart;
    field $input_text;
    field %nonterminals;
    field %leo_items;        # NEW: Track Leo items by (position, symbol)
    field %nullable_cache;   # NEW: Cache nullable computations

    method is_nullable($symbol) {
        return $nullable_cache{$symbol} if exists $nullable_cache{$symbol};
        
        # A symbol is nullable if it can derive the empty string
        if ($symbol eq 'WS') {  # Your WS rule has empty production
            return $nullable_cache{$symbol} = 1;
        }
        
        # Check if any rule for this symbol has all nullable RHS
        for my $rule (@grammar_rules) {
            if ($rule->lhs eq $symbol) {
                if ($rule->rhs_length == 0) {  # Empty RHS
                    return $nullable_cache{$symbol} = 1;
                }
                
                my $all_nullable = 1;
                for my $rhs_symbol ($rule->rhs->@*) {
                    unless ($self->is_nullable($rhs_symbol)) {
                        $all_nullable = 0;
                        last;
                    }
                }
                if ($all_nullable) {
                    return $nullable_cache{$symbol} = 1;
                }
            }
        }
        
        return $nullable_cache{$symbol} = 0;
    }

    method get_leo_item($pos, $symbol) {
        return $leo_items{"$pos:$symbol"};
    }

    method set_leo_item($pos, $symbol, $item) {
        $leo_items{"$pos:$symbol"} = $item;
    }
}
```

### 4. Modified Completion Algorithm

Replace the current completion method with Leo-aware version:

```perl
method complete($item, $pos, $agenda) {
    DEBUG "Completing item " . $item->to_string;
    my $rule = $item->rule;
    my @child_values = $self->collect_child_values($item, $pos);

    # Execute semantic action
    my $semantic_value = undef;
    try {
        DEBUG "Executing semantic action for rule: " . $rule->to_string;
        $semantic_value = $rule->execute_action(\@child_values, $ir_graph);
    }
    catch($e) {
        warn "Error executing semantic action for rule " . $rule->id . ": $e";
    }

    $item->set_semantic_value($semantic_value);

    # NEW: Check for Leo completion first
    my $leo_item = $self->get_leo_item($item->start_pos, $rule->lhs);
    if ($leo_item) {
        DEBUG "Found Leo item for " . $rule->lhs . " at " . $item->start_pos;
        # Leo completion: jump directly to the Leo item
        my $new_item = $leo_item->advance();
        $new_item->set_current_pos($pos);
        $new_item->set_semantic_value($semantic_value);
        push @$agenda, $new_item;
        push @{$chart[$pos]}, $new_item;
        return;  # Skip normal completion
    }

    # Normal Earley completion (unchanged)
    for my $waiting_item (@{$chart[$item->start_pos]}) {
        next if $waiting_item->is_complete;
        next unless defined $waiting_item->next_symbol;
        next unless $waiting_item->next_symbol eq $rule->lhs;

        my $new_item = $waiting_item->advance;
        $new_item->set_current_pos($pos);
        
        # NEW: Check if this creates a Leo-eligible situation
        if ($self->is_leo_eligible($new_item)) {
            my $leo_item = $new_item->create_leo_item($waiting_item, $rule->lhs);
            $self->set_leo_item($waiting_item->start_pos, $rule->lhs, $leo_item);
            DEBUG "Created Leo item for " . $rule->lhs . " at " . $waiting_item->start_pos;
        }
        
        push @$agenda, $new_item;
        push @{$chart[$pos]}, $new_item;
    }
}
```

### 5. Enhanced Prediction

Update prediction method to detect Leo-eligible predictions:

```perl
method predict($item, $pos, $agenda) {
    my $next_sym = $item->next_symbol;
    DEBUG "Predicting for symbol: $next_sym at position $pos";

    for my $rule (@grammar_rules) {
        if ($rule->lhs eq $next_sym) {
            DEBUG "Found rule to predict: " . $rule->to_string;
            
            # Check if already predicted
            my $already_predicted = 0;
            for my $existing_item (@{$chart[$pos]}) {
                if ($existing_item->rule == $rule && 
                    $existing_item->start_pos == $pos && 
                    $existing_item->dot_pos == 0) {
                    $already_predicted = 1;
                    last;
                }
            }
            next if $already_predicted;

            my $predicted_item = EarleyItem->new(
                rule => $rule,
                start_pos => $pos,
                current_pos => $pos
            );

            # NEW: Check if this prediction could benefit from Leo items
            if ($self->is_leo_eligible($predicted_item)) {
                DEBUG "Predicted item is Leo-eligible: " . $rule->to_string;
            }

            push @$agenda, $predicted_item;
            push @{$chart[$pos]}, $predicted_item;
        }
    }
}
```

## Testing Leo Items

### Performance Test

Create test cases with progressively longer strings:

```perl
#!/usr/bin/env perl
use v5.42;
use Time::HiRes qw(time);

my $parser = ScanlessEarleyParser->new();

# Test strings of different lengths
my @test_cases = (
    '"hello"',                    # 5 chars
    '"' . 'x' x 50 . '"',        # 50 chars  
    '"' . 'y' x 500 . '"',       # 500 chars
    '"' . 'z' x 5000 . '"',      # 5000 chars
);

for my $test_string (@test_cases) {
    my $length = length($test_string) - 2;  # Subtract quotes
    
    my $start_time = time();
    my $ir_graph = $parser->parse("print $test_string;");
    my $elapsed = time() - $start_time;
    
    printf "String length: %d chars, Parse time: %.4f seconds\n", 
           $length, $elapsed;
}
```

### Expected Results

**Before Leo Items**:
```
String length: 5 chars, Parse time: 0.0010 seconds
String length: 50 chars, Parse time: 0.0250 seconds  
String length: 500 chars, Parse time: 2.5000 seconds (quadratic growth)
String length: 5000 chars, Parse time: 250+ seconds (unusable)
```

**After Leo Items**:
```
String length: 5 chars, Parse time: 0.0008 seconds
String length: 50 chars, Parse time: 0.0080 seconds
String length: 500 chars, Parse time: 0.0800 seconds (linear growth)
String length: 5000 chars, Parse time: 0.8000 seconds (manageable)
```

## Debugging Leo Items

Add debug output to trace Leo item creation and usage:

```perl
method complete($item, $pos, $agenda) {
    # ... existing code ...
    
    my $leo_item = $self->get_leo_item($item->start_pos, $rule->lhs);
    if ($leo_item) {
        DEBUG "LEO JUMP: Found Leo item for " . $rule->lhs . 
              " at " . $item->start_pos . 
              " -> jumping to position " . $pos;
        # ... Leo completion logic ...
    }
}
```

## Implementation Notes

### Correctness Considerations

1. **Semantic Actions**: Leo items must preserve semantic action execution order
2. **Ambiguity**: Leo items work best with unambiguous right recursion
3. **Left Recursion**: Leo items don't help with left-recursive rules

### Edge Cases to Test

1. **Empty Rules**: Rules with nullable right-hand sides
2. **Mixed Recursion**: Rules with both left and right recursion
3. **Nested Recursion**: Multiple levels of recursive calls
4. **Ambiguous Grammars**: Multiple derivations for the same input

### Performance Monitoring

Add metrics to track Leo item effectiveness:

```perl
field $leo_items_created = 0;
field $leo_jumps_performed = 0;
field $items_avoided = 0;

method report_leo_stats() {
    say "Leo Items Created: $leo_items_created";
    say "Leo Jumps Performed: $leo_jumps_performed";
    say "Items Avoided: $items_avoided";
    say "Efficiency Gain: " . ($items_avoided / ($leo_items_created || 1));
}
```

## Alternative Approach: Left Recursion

Instead of implementing Leo items, you could convert right recursion to left recursion:

```perl
# Current (right recursive):
CharSeq -> Char CharSeq
CharSeq -> Char

# Alternative (left recursive):
CharSeq -> CharSeq Char  
CharSeq -> Char
```

**Pros**: Simpler implementation, naturally linear
**Cons**: Changes semantic action order, requires grammar restructuring

## Integration with Distributed Parser

Leo items provide several benefits for the distributed parsing system:

1. **Predictable Performance**: Linear parsing time enables reliable throughput estimates
2. **Memory Efficiency**: Fewer items created means less memory pressure
3. **Scalability**: Better single-node performance improves overall cluster performance
4. **Large File Support**: Can handle very large source files without timeout

## Implementation Priority

**High Priority**: Implement Leo items for CharSeq rules (biggest performance gain)
**Medium Priority**: Extend to other right-recursive patterns in the grammar
**Low Priority**: Add comprehensive Leo item debugging and monitoring tools

## References

- Leo, Joop M.I.M. "A General Context-Free Parsing Algorithm Running in Linear Time on Every LR(k) Grammar without Using Lookahead" (1991)
- Aycock, John and Horspool, R. Nigel. "Practical Earley Parsing" (2002)
- Marpa parser implementation as reference for production-quality Leo items

## External Links

- [Marpa Parser Project](https://jeffreykegler.github.io/Marpa-web-site/) - Production implementation of Leo items and other Earley optimizations
- [Marpa GitHub Repository](https://github.com/jeffreykegler/Marpa--R2) - Source code reference for Leo item implementation
- [Leo's Original Paper (PDF)](https://www.sciencedirect.com/science/article/pii/030439759190180A) - Theoretical foundation for Leo items optimization
- [Aycock & Horspool "Practical Earley Parsing"](https://web.cs.ualberta.ca/~horspool/papers/ei.pdf) - Practical optimizations for Earley parsers
- [Wikipedia: Earley Parser](https://en.wikipedia.org/wiki/Earley_parser) - General background on Earley parsing algorithm

---

*This document provides a complete roadmap for adding Leo item optimization to the Onyx parser. The implementation should be done incrementally with extensive testing to ensure correctness while achieving the desired performance improvements.*