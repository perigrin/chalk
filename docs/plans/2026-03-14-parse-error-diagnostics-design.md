# Parse Error Diagnostics Design

## Goal

When the Earley parser fails to recognize input, report WHERE the parse
stalled and WHAT was expected, using Rust-style formatted diagnostics.
Currently `parse_value` returns undef with no explanation.

## Scope

Parse-level diagnostics only. Semantic error reporting (type mismatches
from TypeInference) is deferred to a future iteration.

## Output Format

Rust-style, plain ASCII, no emoji:

```
error: parse failed at line 12, column 5
  --> lib/Chalk/Bootstrap/Perl/Target/XS.pm:12:5
   |
10 |
11 | class Chalk::Bootstrap::Perl::Target::XS :isa(Chalk::Bootstrap::Target) {
12 |     field $module_name :param :reader;
   |     ^^^^^
13 |     field $field_map;
   |
   = expected: ClassDeclaration, Statement, '}'
   = note: parsing stopped at 572 of 266471 bytes (0.2%)
```

Components:
- Header with line:col
- File path (or `<input>` if not provided)
- Source context: ±2 lines around failure, numbered
- Caret `^` markers at the stall character
- Expected tokens sorted alphabetically, truncated at 10
- Progress note showing bytes parsed vs total

## API Change

`parse_value` gains an optional `file` parameter:

```perl
# Existing (unchanged):
my $result = $parser->parse_value($source);

# With file path for diagnostics:
my $result = $parser->parse_value($source, file => $path);
```

Return contract unchanged: returns semiring value on success, undef on
failure. Diagnostics go to STDERR via `warn()`.

## Implementation

### 1. Track furthest active position in `_run_parse`

Add `$last_active_pos` tracking to the main position loop:

```perl
my $last_active_pos = 0;
for my $pos (0 .. $n) {
    # ... build agenda ...
    $last_active_pos = $pos if @agenda;
    # ... process agenda ...
}
```

Cost: one scalar comparison per position. Negligible.

### 2. Snapshot expected tokens on failure

Before returning undef, extract expected symbols from items at
`$last_active_pos` where the dot is not at the end of the rule:

```perl
my %expected;
for my $origin_hash ($chart[$last_active_pos]->@*) {
    next unless defined $origin_hash;
    for my $entry (values $origin_hash->%*) {
        my $item = $entry->[0];
        my $info = $core_index->item_for($item->{core_id});
        my $rhs = $rule_table->{$info->{rule_name}}
                    ->expressions->[$info->{alt}];
        if ($info->{dot} < scalar($rhs->@*)) {
            my $next = $rhs->[$info->{dot}];
            $expected{$next->value()} = 1;
        }
    }
}
```

### 3. Format and warn

New method `_format_parse_error($input, $last_active_pos, \%expected, %opts)`:

1. Count newlines up to `$last_active_pos` for line:col
2. Split input, extract ±2 context lines
3. Build the Rust-style formatted string
4. `warn($formatted)`
5. Return undef

### 4. Wire into parse_value

```perl
method parse_value($input, %opts) {
    return $self->_run_parse($input, %opts);
}
```

`_run_parse` passes `%opts` through to the error formatter for the `file`
key.

## XS Compatibility

- `warn()` already compiles to `Perl_warn(aTHX_ "%s", ...)` — no eval_pv
- `_format_parse_error` is a regular method, compiles like any other
- String formatting (sprintf, join, substr) all have XS codegen support
- Only fires on parse failure, not on the hot path

## GC Interaction

The chart is GC'd aggressively during parsing (`_gc_stats`). The failure
position's chart entries might have been freed if `$last_active_pos` is
far behind the current position.

Mitigation: also track `$last_active_items` — snapshot the expected
symbols at each new `$last_active_pos` so they survive GC. This is a
small hash updated only when `$last_active_pos` advances.

## Files Modified

- `lib/Chalk/Bootstrap/Earley.pm` — all changes
- `t/bootstrap/earley-diagnostics.t` — new test file

## Testing

1. Parse a known-good input, verify no warning emitted
2. Parse a truncated input, verify warning contains correct line:col
3. Parse input with known grammar gap, verify expected tokens are sensible
4. Verify `file` parameter appears in output
5. Verify `<input>` default when no file given
