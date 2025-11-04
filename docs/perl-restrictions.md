# Chalk Restrictions from Standard Perl

This document lists features of Perl that are intentionally restricted or modified in Chalk due to architectural decisions.

## Function Call Syntax

**Flexibility:** Function and method calls in Chalk may omit parentheses in unambiguous contexts.

**What works:**
```perl
foo(1, 2);           # Traditional with parentheses
foo 1, 2;            # Without parentheses (list context clear)
$obj->method($arg);  # Method with parentheses
$obj->method;        # Method without parentheses
```

**Rationale:** While Standard Perl requires parentheses for all function calls to eliminate parsing ambiguity, Chalk's grammar can statically parse certain parenthesis-free forms. This is supported through the grammar rules:
- `FunctionCall -> Identifier WS Expression` (line 315)
- `MethodCall -> Expression '->' Identifier` (line 325)

The precedence semiring validates that these constructs don't create ambiguity with operators.

## References and Mutation

**Restriction:** References in Chalk are immutable aliases, not mutable pointers.

**Rationale:** Chalk uses SSA (Static Single Assignment) form for its IR, where all values are immutable. This provides benefits for optimization and analysis but prevents mutation through references.

**What works:**
```perl
my $x = 10;
my $ref = \$x;   # Creates an alias to the same value
my $y = $$ref;   # $y = 10 (dereference returns the value)
```

**What doesn't work:**
```perl
my $x = 10;
my $ref = \$x;
$$ref = 20;      # ERROR: Cannot mutate through references in Chalk
```

**Standard Perl behavior:**
```perl
my $x = 10;
my $ref = \$x;
$$ref = 20;
print $x;        # Prints 20 (mutation through reference)
```

**Chalk behavior:**
```perl
my $x = 10;
my $ref = \$x;
# $$ref = 20;    # This would be a compile-time error
my $x = 20;      # Must rebind the variable instead (creates new SSA node)
print $x;        # Prints 20
```

## Implementation Details

In Chalk's SSA IR:
- Variables are bindings to immutable nodes
- `\$x` creates a reference that shares the same node binding
- `$$ref` inlines the referenced node (same as using the original variable)
- There is no "heap" with mutable memory locations

This is similar to functional programming languages where references are just shared bindings to immutable values.
