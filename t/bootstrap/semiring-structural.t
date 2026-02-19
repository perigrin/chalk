# ABOUTME: Tests for Structural semiring that disambiguates Block vs HashConstructor.
# ABOUTME: Covers basic ops, tagging, boundary resets, add() preference, and parser integration.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# ========================================================================
# Phase 1: Basic semiring operations (zero, one, is_zero, multiply, add)
# ========================================================================
use_ok('Chalk::Bootstrap::Semiring::Structural');

my $sr = Chalk::Bootstrap::Semiring::Structural->new();

# --- Bitfield representation tests ---
# Verify the integer bitfield encoding: zero=-1 (sentinel), one=0 (no bits set),
# bit positions for each structural tag.
{
    my $z = $sr->zero();
    is($z, -1, 'zero() returns -1 (sentinel outside 0-255 range)');

    my $o = $sr->one();
    is($o, 0, 'one() returns 0 (no bits set, valid)');

    ok($sr->is_zero(-1), 'is_zero(-1) returns true');
    ok(!$sr->is_zero(0),  'is_zero(0) returns false (one is not zero)');
}

# Verify the bit position constants are correct
{
    use Chalk::Bootstrap::Semiring::Structural qw(
        STRUCT_IS_BLOCK  STRUCT_IS_HASH    STRUCT_IS_CALL
        STRUCT_IS_LIST   STRUCT_IS_DEREF   STRUCT_IS_METHOD
        STRUCT_IS_BINOP  STRUCT_IS_VARDECL
    );

    is(STRUCT_IS_BLOCK,   1,   'STRUCT_IS_BLOCK   = bit 0 (1)');
    is(STRUCT_IS_HASH,    2,   'STRUCT_IS_HASH    = bit 1 (2)');
    is(STRUCT_IS_CALL,    4,   'STRUCT_IS_CALL    = bit 2 (4)');
    is(STRUCT_IS_LIST,    8,   'STRUCT_IS_LIST    = bit 3 (8)');
    is(STRUCT_IS_DEREF,   16,  'STRUCT_IS_DEREF   = bit 4 (16)');
    is(STRUCT_IS_METHOD,  32,  'STRUCT_IS_METHOD  = bit 5 (32)');
    is(STRUCT_IS_BINOP,   64,  'STRUCT_IS_BINOP   = bit 6 (64)');
    is(STRUCT_IS_VARDECL, 128, 'STRUCT_IS_VARDECL = bit 7 (128)');
}

# Verify multiply with integer values
{
    my $block_val = STRUCT_IS_BLOCK;   # 1
    my $hash_val  = STRUCT_IS_HASH;    # 2
    my $plain     = $sr->one();        # 0

    my $r1 = $sr->multiply($block_val, $plain);
    ok($r1 & STRUCT_IS_BLOCK, 'block bit propagates from left in multiply (integer)');

    my $r2 = $sr->multiply($plain, $hash_val);
    ok($r2 & STRUCT_IS_HASH, 'hash bit propagates from right in multiply (integer)');

    my $r3 = $sr->multiply($block_val, $hash_val);
    ok($r3 & STRUCT_IS_BLOCK, 'both bits: block propagates in multiply (integer)');
    ok($r3 & STRUCT_IS_HASH,  'both bits: hash propagates in multiply (integer)');
}

# Verify zero() propagation in multiply with integers
{
    ok($sr->is_zero($sr->multiply(-1, 0)), 'multiply(zero, one) = zero (integer)');
    ok($sr->is_zero($sr->multiply(0, -1)), 'multiply(one, zero) = zero (integer)');
    ok(!$sr->is_zero($sr->multiply(0, 0)), 'multiply(one, one) = non-zero (integer)');
}

# --- zero / one / is_zero (new integer representation) ---
{
    my $z = $sr->zero();
    ok($sr->is_zero($z), 'zero is zero');

    my $o = $sr->one();
    ok(!$sr->is_zero($o), 'one is not zero');
}

# --- multiply: zero propagation ---
{
    my $z = $sr->zero();
    my $o = $sr->one();

    ok($sr->is_zero($sr->multiply($z, $o)), 'zero * one = zero');
    ok($sr->is_zero($sr->multiply($o, $z)), 'one * zero = zero');
    ok($sr->is_zero($sr->multiply($z, $z)), 'zero * zero = zero');
    ok(!$sr->is_zero($sr->multiply($o, $o)), 'one * one is not zero');
}

# --- multiply: tag propagation ---
{
    use Chalk::Bootstrap::Semiring::Structural qw(
        STRUCT_IS_BLOCK STRUCT_IS_HASH STRUCT_IS_CALL STRUCT_IS_DEREF
        STRUCT_IS_METHOD STRUCT_IS_BINOP STRUCT_IS_VARDECL STRUCT_IS_LIST
    );

    my $block_val = STRUCT_IS_BLOCK;
    my $hash_val  = STRUCT_IS_HASH;
    my $plain     = $sr->one();

    my $r1 = $sr->multiply($block_val, $plain);
    ok($r1 & STRUCT_IS_BLOCK, 'block tag propagates from left through multiply');

    my $r2 = $sr->multiply($plain, $hash_val);
    ok($r2 & STRUCT_IS_HASH, 'hash tag propagates from right through multiply');

    my $r3 = $sr->multiply($block_val, $hash_val);
    ok($r3 & STRUCT_IS_BLOCK, 'both tags: block propagates through multiply');
    ok($r3 & STRUCT_IS_HASH,  'both tags: hash propagates through multiply');
}

# --- multiply: is_deref tag propagation ---
{
    my $deref_val  = STRUCT_IS_DEREF;
    my $plain      = $sr->one();

    my $r1 = $sr->multiply($deref_val, $plain);
    ok($r1 & STRUCT_IS_DEREF, 'is_deref propagates from left through multiply');

    my $r2 = $sr->multiply($plain, $deref_val);
    ok($r2 & STRUCT_IS_DEREF, 'is_deref propagates from right through multiply');

    my $call_deref = STRUCT_IS_CALL | STRUCT_IS_DEREF;
    my $r3 = $sr->multiply($call_deref, $plain);
    ok($r3 & STRUCT_IS_CALL,  'is_call preserved alongside is_deref in multiply');
    ok($r3 & STRUCT_IS_DEREF, 'is_deref preserved alongside is_call in multiply');
}

# --- multiply: is_method tag propagation ---
{
    my $method_val = STRUCT_IS_METHOD;
    my $plain      = $sr->one();

    my $r1 = $sr->multiply($method_val, $plain);
    ok($r1 & STRUCT_IS_METHOD, 'is_method propagates from left through multiply');

    my $r2 = $sr->multiply($plain, $method_val);
    ok($r2 & STRUCT_IS_METHOD, 'is_method propagates from right through multiply');

    my $call_method = STRUCT_IS_CALL | STRUCT_IS_METHOD;
    my $r3 = $sr->multiply($call_method, $plain);
    ok($r3 & STRUCT_IS_CALL,   'is_call preserved alongside is_method in multiply');
    ok($r3 & STRUCT_IS_METHOD, 'is_method preserved alongside is_call in multiply');
}

# --- multiply: is_binop tag propagation ---
{
    my $binop_val = STRUCT_IS_BINOP;
    my $plain     = $sr->one();

    my $r1 = $sr->multiply($binop_val, $plain);
    ok($r1 & STRUCT_IS_BINOP, 'is_binop propagates from left through multiply');

    my $r2 = $sr->multiply($plain, $binop_val);
    ok($r2 & STRUCT_IS_BINOP, 'is_binop propagates from right through multiply');
}

# --- multiply: is_vardecl tag propagation ---
{
    my $vardecl_val = STRUCT_IS_VARDECL;
    my $plain       = $sr->one();

    my $r1 = $sr->multiply($vardecl_val, $plain);
    ok($r1 & STRUCT_IS_VARDECL, 'is_vardecl propagates from left through multiply');

    my $r2 = $sr->multiply($plain, $vardecl_val);
    ok($r2 & STRUCT_IS_VARDECL, 'is_vardecl propagates from right through multiply');
}

# --- add: first non-zero when one is zero ---
{
    my $z = $sr->zero();
    my $o = $sr->one();

    my $r1 = $sr->add($z, $o);
    ok(!$sr->is_zero($r1), 'add(zero, one) = non-zero');

    my $r2 = $sr->add($o, $z);
    ok(!$sr->is_zero($r2), 'add(one, zero) = non-zero');

    ok($sr->is_zero($sr->add($z, $z)), 'add(zero, zero) = zero');
}

# --- add: prefer is_block over is_hash ---
{
    my $block_val = STRUCT_IS_BLOCK;
    my $hash_val  = STRUCT_IS_HASH;

    my $r1 = $sr->add($block_val, $hash_val);
    ok($r1 & STRUCT_IS_BLOCK,  'add(block, hash) prefers block');
    ok(!($r1 & STRUCT_IS_HASH), 'add(block, hash) does not carry hash tag');

    my $r2 = $sr->add($hash_val, $block_val);
    ok($r2 & STRUCT_IS_BLOCK,  'add(hash, block) still prefers block');
    ok(!($r2 & STRUCT_IS_HASH), 'add(hash, block) does not carry hash tag');
}

# --- add: prefer is_call over is_call+is_deref ---
# When both alternatives have is_call, prefer the one WITHOUT is_deref.
# This disambiguates CallExpression vs PostfixDeref-on-CallExpression.
{
    my $call_only  = STRUCT_IS_CALL;
    my $call_deref = STRUCT_IS_CALL | STRUCT_IS_DEREF;

    my $r1 = $sr->add($call_only, $call_deref);
    ok($r1 & STRUCT_IS_CALL,   'add(call, call+deref): has is_call');
    ok(!($r1 & STRUCT_IS_DEREF), 'add(call, call+deref): prefers no is_deref');

    my $r2 = $sr->add($call_deref, $call_only);
    ok($r2 & STRUCT_IS_CALL,   'add(call+deref, call): has is_call');
    ok(!($r2 & STRUCT_IS_DEREF), 'add(call+deref, call): prefers no is_deref');
}

# --- add: prefer is_call over is_call+is_method ---
# When both alternatives have is_call, prefer the one WITHOUT is_method.
# This disambiguates CallExpression vs MethodCall at PostfixExpression level.
{
    my $call_only   = STRUCT_IS_CALL;
    my $call_method = STRUCT_IS_CALL | STRUCT_IS_METHOD;

    my $r1 = $sr->add($call_only, $call_method);
    ok($r1 & STRUCT_IS_CALL,     'add(call, call+method): has is_call');
    ok(!($r1 & STRUCT_IS_METHOD), 'add(call, call+method): prefers no is_method');

    my $r2 = $sr->add($call_method, $call_only);
    ok($r2 & STRUCT_IS_CALL,     'add(call+method, call): has is_call');
    ok(!($r2 & STRUCT_IS_METHOD), 'add(call+method, call): prefers no is_method');
}

# --- add: prefer is_call over is_call+is_binop ---
# When both alternatives have is_call, prefer the one WITHOUT is_binop.
# This disambiguates CallExpression vs BinaryExpression with inherited is_call.
{
    my $call_only  = STRUCT_IS_CALL;
    my $call_binop = STRUCT_IS_CALL | STRUCT_IS_BINOP;

    my $r1 = $sr->add($call_only, $call_binop);
    ok($r1 & STRUCT_IS_CALL,    'add(call, call+binop): has is_call');
    ok(!($r1 & STRUCT_IS_BINOP), 'add(call, call+binop): prefers no is_binop');

    my $r2 = $sr->add($call_binop, $call_only);
    ok($r2 & STRUCT_IS_CALL,    'add(call+binop, call): has is_call');
    ok(!($r2 & STRUCT_IS_BINOP), 'add(call+binop, call): prefers no is_binop');
}

# --- add: prefer is_vardecl over non-is_vardecl ---
# When both alternatives have is_binop (or identical tags), prefer the one
# with is_vardecl. This disambiguates VariableDeclaration-based statements
# from bogus parses where `my` is treated as a bare identifier.
{
    my $binop_only    = STRUCT_IS_BINOP;
    my $binop_vardecl = STRUCT_IS_BINOP | STRUCT_IS_VARDECL;

    my $r1 = $sr->add($binop_only, $binop_vardecl);
    ok($r1 & STRUCT_IS_VARDECL, 'add(binop, binop+vardecl): prefers is_vardecl');
    ok($r1 & STRUCT_IS_BINOP,   'add(binop, binop+vardecl): preserves is_binop');

    my $r2 = $sr->add($binop_vardecl, $binop_only);
    ok($r2 & STRUCT_IS_VARDECL, 'add(binop+vardecl, binop): prefers is_vardecl');
}

# --- add: both valid, neither tagged ---
{
    my $o1 = $sr->one();
    my $o2 = $sr->one();

    my $r = $sr->add($o1, $o2);
    ok(!$sr->is_zero($r), 'add(one, one) is not zero');
    # Both are 0 (one), result should be 0 (valid, no tags)
    is($r, 0, 'add(one, one) is valid (integer 0)');
}

# --- selects_alternative: is_deref disambiguation ---
{
    my $call_only  = STRUCT_IS_CALL;
    my $call_deref = STRUCT_IS_CALL | STRUCT_IS_DEREF;

    is($sr->selects_alternative($call_only, $call_deref), 'left',
        'selects_alternative(call, call+deref) returns left');
    is($sr->selects_alternative($call_deref, $call_only), 'right',
        'selects_alternative(call+deref, call) returns right');

    # Both have is_deref — identical tags, pick left to break tie
    is($sr->selects_alternative($call_deref, $call_deref), 'left',
        'selects_alternative(call+deref, call+deref) returns left (identical tags)');
}

# --- selects_alternative: is_method disambiguation ---
{
    my $call_only   = STRUCT_IS_CALL;
    my $call_method = STRUCT_IS_CALL | STRUCT_IS_METHOD;

    is($sr->selects_alternative($call_only, $call_method), 'left',
        'selects_alternative(call, call+method) returns left');
    is($sr->selects_alternative($call_method, $call_only), 'right',
        'selects_alternative(call+method, call) returns right');

    # Both have is_method — identical tags, pick left to break tie
    is($sr->selects_alternative($call_method, $call_method), 'left',
        'selects_alternative(call+method, call+method) returns left (identical tags)');
}

# --- selects_alternative: is_binop disambiguation ---
{
    my $call_only  = STRUCT_IS_CALL;
    my $call_binop = STRUCT_IS_CALL | STRUCT_IS_BINOP;

    is($sr->selects_alternative($call_only, $call_binop), 'left',
        'selects_alternative(call, call+binop) returns left');
    is($sr->selects_alternative($call_binop, $call_only), 'right',
        'selects_alternative(call+binop, call) returns right');

    # Both have is_binop — identical tags, pick left to break tie
    is($sr->selects_alternative($call_binop, $call_binop), 'left',
        'selects_alternative(call+binop, call+binop) returns left (identical tags)');
}

# --- selects_alternative: is_vardecl disambiguation ---
{
    my $binop_only    = STRUCT_IS_BINOP;
    my $binop_vardecl = STRUCT_IS_BINOP | STRUCT_IS_VARDECL;

    is($sr->selects_alternative($binop_only, $binop_vardecl), 'right',
        'selects_alternative(binop, binop+vardecl) returns right');
    is($sr->selects_alternative($binop_vardecl, $binop_only), 'left',
        'selects_alternative(binop+vardecl, binop) returns left');

    # Both have is_vardecl — identical tags, fall through to binop tie-breaker
    is($sr->selects_alternative($binop_vardecl, $binop_vardecl), 'left',
        'selects_alternative(binop+vardecl, binop+vardecl) returns left (identical binop tags)');
}

# --- selects_alternative: is_binop identical-tag tie-breaking ---
# Chained BinaryExpressions (e.g. $a && $b && $c) produce two alternatives
# with identical structural tags. Pick left for left-associative grouping.
{
    my $binop_only  = STRUCT_IS_BINOP;
    my $binop_deref = STRUCT_IS_BINOP | STRUCT_IS_DEREF;

    is($sr->selects_alternative($binop_only, $binop_only), 'left',
        'selects_alternative(binop, binop) identical tags returns left');
    is($sr->selects_alternative($binop_deref, $binop_deref), 'left',
        'selects_alternative(binop+deref, binop+deref) identical tags returns left');
}

# ========================================================================
# Phase 2: on_scan (transparency)
# ========================================================================

# Mock item for on_scan/on_complete testing
my sub mock_item($rule_name, $value) {
    return {
        rule  => bless({ _name => $rule_name }, 'MockRule'),
        value => $value,
    };
}

# Provide a name() method for MockRule
{
    package MockRule;
    sub name { return $_[0]->{_name} }
}

{
    my $o = $sr->one();
    my $item = mock_item('Identifier', $o);
    my $r = $sr->on_scan($item, 0, 0, 'foo');
    ok(!$sr->is_zero($r), 'on_scan is transparent for Identifier');
    # one() = 0, on_scan returns 0 (valid, no tags)
    is($r, 0, 'on_scan of one() returns integer 0');
}

{
    my $z = $sr->zero();
    my $item = mock_item('Identifier', $z);
    my $r = $sr->on_scan($item, 0, 0, 'foo');
    ok($sr->is_zero($r), 'on_scan propagates zero');
}

{
    my $block_val = STRUCT_IS_BLOCK;
    my $item = mock_item('Block', $block_val);
    my $r = $sr->on_scan($item, 0, 0, '{');
    ok($r & STRUCT_IS_BLOCK, 'on_scan preserves block tag through multiply');
}

# ========================================================================
# Phase 3: on_complete (tagging and boundary clearing)
# ========================================================================

# --- Block completion → is_block tag ---
{
    my $o = $sr->one();
    my $item = mock_item('Block', $o);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'Block completion is valid');
    ok($r & STRUCT_IS_BLOCK,   'Block completion sets is_block tag');
    ok(!($r & STRUCT_IS_HASH), 'Block completion does not set is_hash');
}

# --- HashConstructor completion → is_hash tag ---
{
    my $o = $sr->one();
    my $item = mock_item('HashConstructor', $o);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'HashConstructor completion is valid');
    ok($r & STRUCT_IS_HASH,     'HashConstructor completion sets is_hash tag');
    ok(!($r & STRUCT_IS_BLOCK), 'HashConstructor completion does not set is_block');
}

# --- PostfixDeref completion → is_deref tag (clears is_call from child) ---
# PostfixDeref is a dereference, not a function call. Clearing is_call allows
# add() to prefer CallExpression (is_call) over PostfixDeref (is_deref only)
# via the "prefer is_call over non-call" rule.
{
    my $call_val = STRUCT_IS_CALL;
    my $item = mock_item('PostfixDeref', $call_val);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'PostfixDeref completion is valid');
    ok($r & STRUCT_IS_DEREF,   'PostfixDeref completion sets is_deref');
    ok(!($r & STRUCT_IS_CALL), 'PostfixDeref completion clears is_call from child');
}

{
    my $plain = $sr->one();
    my $item = mock_item('PostfixDeref', $plain);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'PostfixDeref with plain value is valid');
    ok($r & STRUCT_IS_DEREF,   'PostfixDeref with plain value sets is_deref');
    ok(!($r & STRUCT_IS_CALL), 'PostfixDeref with plain value has no is_call');
}

# --- MethodCall completion → is_method tag ---
# All alts get is_method. Alts 0, 2 (with parens) also get is_call.
{
    my $plain = $sr->one();

    # Alt 0: method call with parens
    my $item0 = mock_item('MethodCall', $plain);
    my $r0 = $sr->on_complete($item0, 0, 0);
    ok(!$sr->is_zero($r0), 'MethodCall alt 0 is valid');
    ok($r0 & STRUCT_IS_METHOD, 'MethodCall alt 0 sets is_method');
    ok($r0 & STRUCT_IS_CALL,   'MethodCall alt 0 (with parens) sets is_call');

    # Alt 1: bare method access (no parens)
    my $item1 = mock_item('MethodCall', $plain);
    my $r1 = $sr->on_complete($item1, 1, 0);
    ok(!$sr->is_zero($r1), 'MethodCall alt 1 is valid');
    ok($r1 & STRUCT_IS_METHOD,  'MethodCall alt 1 sets is_method');
    ok(!($r1 & STRUCT_IS_CALL), 'MethodCall alt 1 (bare) does not set is_call');

    # Alt 2: method call with parens (arrow variant)
    my $item2 = mock_item('MethodCall', $plain);
    my $r2 = $sr->on_complete($item2, 2, 0);
    ok($r2 & STRUCT_IS_METHOD, 'MethodCall alt 2 sets is_method');
    ok($r2 & STRUCT_IS_CALL,   'MethodCall alt 2 (with parens) sets is_call');

    # Alt 3: bare method access (arrow variant)
    my $item3 = mock_item('MethodCall', $plain);
    my $r3 = $sr->on_complete($item3, 3, 0);
    ok($r3 & STRUCT_IS_METHOD,  'MethodCall alt 3 sets is_method');
    ok(!($r3 & STRUCT_IS_CALL), 'MethodCall alt 3 (bare) does not set is_call');
}

# --- MethodCall inherits is_call from child ---
{
    my $call_val = STRUCT_IS_CALL;
    my $item = mock_item('MethodCall', $call_val);
    my $r = $sr->on_complete($item, 1, 0);
    ok($r & STRUCT_IS_METHOD, 'MethodCall with is_call child sets is_method');
    ok($r & STRUCT_IS_CALL,   'MethodCall inherits is_call from child even on bare alt');
}

# --- BinaryExpression completion → is_binop tag ---
{
    my $call_val = STRUCT_IS_CALL;
    my $item = mock_item('BinaryExpression', $call_val);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'BinaryExpression completion is valid');
    ok($r & STRUCT_IS_BINOP, 'BinaryExpression sets is_binop');
    ok($r & STRUCT_IS_CALL,  'BinaryExpression preserves is_call from child');
}

# --- VariableDeclaration tags is_vardecl ---
{
    my $plain = $sr->one();   # 0 = no tags
    my $item = mock_item('VariableDeclaration', $plain);
    my $r = $sr->on_complete($item, 0, 0);
    ok($r & STRUCT_IS_VARDECL,  'VariableDeclaration sets is_vardecl');
    ok(!($r & STRUCT_IS_BLOCK), 'VariableDeclaration does not set is_block');
}

# --- CallExpression clears is_deref, is_method, and is_binop ---
{
    my $tagged = STRUCT_IS_DEREF | STRUCT_IS_METHOD | STRUCT_IS_BINOP;
    my $item = mock_item('CallExpression', $tagged);
    my $r = $sr->on_complete($item, 0, 0);
    ok($r & STRUCT_IS_CALL,     'CallExpression sets is_call');
    ok(!($r & STRUCT_IS_DEREF), 'CallExpression clears is_deref from child');
    ok(!($r & STRUCT_IS_METHOD),'CallExpression clears is_method from child');
    ok(!($r & STRUCT_IS_BINOP), 'CallExpression clears is_binop from child');
}

# --- ExpressionList alts 1+ → is_list tag ---
# ExpressionList:0 (single Expression) has no is_list.
# ExpressionList:1 (comma-separated) gets is_list so add() prefers single Expression.
{
    my $deref_val = STRUCT_IS_DEREF;
    my $item0 = mock_item('ExpressionList', $deref_val);
    my $r0 = $sr->on_complete($item0, 0, 0);
    ok(!($r0 & STRUCT_IS_LIST), 'ExpressionList alt 0 (single) has no is_list');
    ok($r0 & STRUCT_IS_DEREF,   'ExpressionList alt 0 preserves is_deref');

    my $item1 = mock_item('ExpressionList', $deref_val);
    my $r1 = $sr->on_complete($item1, 1, 0);
    ok($r1 & STRUCT_IS_LIST,  'ExpressionList alt 1 (comma) sets is_list');
    ok($r1 & STRUCT_IS_DEREF, 'ExpressionList alt 1 preserves is_deref');

    my $item2 = mock_item('ExpressionList', STRUCT_IS_CALL);
    my $r2 = $sr->on_complete($item2, 2, 0);
    ok($r2 & STRUCT_IS_LIST, 'ExpressionList alt 2 (fat arrow) sets is_list');
    ok($r2 & STRUCT_IS_CALL, 'ExpressionList alt 2 preserves is_call');

    my $item3 = mock_item('ExpressionList', $sr->one());  # 0 = no tags
    my $r3 = $sr->on_complete($item3, 3, 0);
    ok($r3 & STRUCT_IS_LIST, 'ExpressionList alt 3 (trailing comma) sets is_list');
}

# --- CallExpression clears is_deref and is_method ---
{
    my $deref_method = STRUCT_IS_DEREF | STRUCT_IS_METHOD;
    my $item = mock_item('CallExpression', $deref_method);
    my $r = $sr->on_complete($item, 0, 0);
    ok($r & STRUCT_IS_CALL,      'CallExpression sets is_call');
    ok(!($r & STRUCT_IS_DEREF),  'CallExpression clears is_deref from child');
    ok(!($r & STRUCT_IS_METHOD), 'CallExpression clears is_method from child');
}

# --- Boundary rules clear tags ---
for my $boundary_rule (qw(ParenExpr ArrayConstructor)) {
    my $tagged = STRUCT_IS_BLOCK | STRUCT_IS_HASH;
    my $item = mock_item($boundary_rule, $tagged);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), "$boundary_rule completion is valid");
    ok(!($r & STRUCT_IS_BLOCK), "$boundary_rule clears is_block tag");
    ok(!($r & STRUCT_IS_HASH),  "$boundary_rule clears is_hash tag");
}

# --- Program/StatementList preserve is_block/is_hash for Block-vs-Hash disambiguation ---
for my $preserve_rule (qw(Program StatementList)) {
    my $tagged = STRUCT_IS_BLOCK | STRUCT_IS_HASH;
    my $item = mock_item($preserve_rule, $tagged);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), "$preserve_rule completion is valid");
    ok($r & STRUCT_IS_BLOCK,  "$preserve_rule preserves is_block tag");
    ok($r & STRUCT_IS_HASH,   "$preserve_rule preserves is_hash tag");
}

# --- Other rules pass through ---
{
    my $block_val = STRUCT_IS_BLOCK;
    my $item = mock_item('Expression', $block_val);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'Expression completion is valid');
    ok($r & STRUCT_IS_BLOCK, 'Expression passes through is_block tag');
}

{
    my $hash_val = STRUCT_IS_HASH;
    my $item = mock_item('Atom', $hash_val);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'Atom completion is valid');
    ok($r & STRUCT_IS_HASH, 'Atom passes through is_hash tag');
}

# --- Zero propagation ---
{
    my $z = $sr->zero();
    my $item = mock_item('Block', $z);
    my $r = $sr->on_complete($item, 0, 0);
    ok($sr->is_zero($r), 'on_complete propagates zero');
}

# --- StatementItem: alts are all valid, no special tagging ---
# (bare statement alt was removed from grammar — all statements need semicolons)
{
    my $o = $sr->one();
    my $item = mock_item('StatementItem', $o);

    # alt_idx 0 = SimpleStatement ";"
    my $r0 = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r0), 'StatementItem alt 0 (with semicolon) is valid');

    # alt_idx 1 = CompoundStatement
    my $r1 = $sr->on_complete($item, 1, 0);
    ok(!$sr->is_zero($r1), 'StatementItem alt 1 (compound) is valid');

    # alt_idx 2 = bare ";"
    my $r2 = $sr->on_complete($item, 2, 0);
    ok(!$sr->is_zero($r2), 'StatementItem alt 2 (bare semicolon) is valid');
}

# --- Block completion ---
{
    my $o = $sr->one();
    my $item = mock_item('Block', $o);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'Block with content is valid');
    ok($r & STRUCT_IS_BLOCK, 'Block completion still sets is_block');
}

# --- StatementList preserves block/hash tags for disambiguation ---
{
    my $tagged = STRUCT_IS_BLOCK | STRUCT_IS_HASH;
    my $item = mock_item('StatementList', $tagged);

    my $r0 = $sr->on_complete($item, 0, 0);
    ok($r0 & STRUCT_IS_BLOCK, 'StatementList preserves is_block');
    ok($r0 & STRUCT_IS_HASH,  'StatementList preserves is_hash');
}

# --- StatementList alts are valid ---
{
    my $o = $sr->one();
    my $item = mock_item('StatementList', $o);
    my $r0 = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r0), 'StatementList alt 0 is valid');

    my $r1 = $sr->on_complete($item, 1, 0);
    ok(!$sr->is_zero($r1), 'StatementList alt 1 is valid');
}

# ========================================================================
# Phase 4: Integration with full Earley parser
# Uses Bool+Structural only to isolate the Structural semiring's behavior
# from pre-existing nondeterminism in Precedence/TypeInference add().
# ========================================================================
use TestPipeline qw(perl_pipeline);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Composite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Desugar;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 15 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::StructuralInteg/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 15 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::StructuralInteg::grammar();
    my @reordered;
    my $found = false;
    for my $rule ($gen_grammar->@*) {
        if (!$found && $rule->name() eq 'Program') {
            unshift @reordered, $rule;
            $found = true;
        } else {
            push @reordered, $rule;
        }
    }
    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@reordered);

    # 2-ary composite: Bool + Structural (no Prec/TypeInf/Semantic)
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();

    my $comp_sr = Chalk::Bootstrap::Semiring::Composite->new(
        semirings => [$bool_sr, $struct_sr],
    );

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $comp_sr,
    );

    # Helper: parse and return result tuple [0]=Boolean, [1]=Structural
    my sub parse_result($source) {
        return $parser->parse_value($source);
    }

    # Helper: extract Structural value from result
    my sub struct_val($result) {
        return $result->[1] if defined $result;
        return undef;
    }

    # --- { 42; } at statement level: with semicolon, unambiguous Block ---
    {
        my $result = parse_result('{ 42; }');
        ok(defined $result, '{ 42; } parses at statement level');
        my $sv = struct_val($result);
        ok(!$struct_sr->is_zero($sv), '{ 42; } structural value is valid (not zero)');
        # At statement level, Block should be preferred
        ok(($sv & STRUCT_IS_BLOCK) || !($sv & STRUCT_IS_HASH),
            '{ 42; } at statement level: block preferred or hash not tagged');
    }

    # --- { } at statement level: ambiguous, should prefer Block ---
    {
        my $result = parse_result('{ }');
        ok(defined $result, '{ } parses at statement level');
        my $sv = struct_val($result);
        ok(!$struct_sr->is_zero($sv), '{ } structural value is valid (not zero)');
        ok(($sv & STRUCT_IS_BLOCK) || !($sv & STRUCT_IS_HASH),
            '{ } at statement level: block preferred or hash not tagged');
    }

    # --- { $x => $y } : naturally unambiguous → HashConstructor ---
    {
        my $result = parse_result('my $h = { $x => $y };');
        ok(defined $result, '{ $x => $y } in assignment parses');
    }

    # --- { my $x = 42; } : semicolon makes it unambiguous Block ---
    {
        my $result = parse_result('{ my $x = 42; }');
        ok(defined $result, '{ my $x = 42; } parses');
    }

    # --- Simple non-brace programs still work ---
    {
        my $result = parse_result('my $x = 42;');
        ok(defined $result, 'simple declaration still parses');
        my $sv = struct_val($result);
        ok(!$struct_sr->is_zero($sv), 'simple declaration structural value is valid (not zero)');
        # No block or hash tags for non-brace content (Program clears them)
        ok(!($sv & STRUCT_IS_BLOCK) && !($sv & STRUCT_IS_HASH),
            'simple declaration has no block/hash tags');
    }

    # --- Multiple statements with blocks ---
    {
        my $result = parse_result('my $x = 1; { my $y = 2; }');
        ok(defined $result, 'statement + block parses');
    }

    # --- Sub with block body ---
    {
        my $result = parse_result('sub foo { }');
        ok(defined $result, 'sub with empty block parses');
    }

    # --- if/while with blocks (control flow) ---
    {
        my $result = parse_result('if ($x) { my $y = 1; }');
        ok(defined $result, 'if with block body parses');
    }

    {
        my $result = parse_result('while ($x) { my $y = 1; }');
        ok(defined $result, 'while with block body parses');
    }

    # --- Expression separator disambiguation ---
    # These test that ambiguous operators (+, -, //) are parsed as binary
    # operators rather than starting a new unseparated statement.

    # Binary + should not be split into bare $a + unary +$b
    {
        my $result = parse_result('my $a = 1; my $c = $a + 3;');
        ok(defined $result, 'binary + in assignment parses');
    }

    # Binary - should not be split into bare $a + unary -$b
    {
        my $result = parse_result('my $a = 1; my $c = $a - 3;');
        ok(defined $result, 'binary - in assignment parses');
    }

    # // (defined-or) should not be parsed as empty regex literal
    {
        my $result = parse_result('my $a = 0; my $b = $a // 1;');
        ok(defined $result, 'defined-or (//) in assignment parses');
    }

    # //= (compound defined-or assign)
    {
        my $result = parse_result('my $a = 0; $a //= 1;');
        ok(defined $result, 'compound //= parses');
    }

    # --- PostfixDeref vs CallExpression disambiguation ---
    # push $ops->@*, $op  should parse as CallExpression (push takes the list),
    # not as PostfixDeref on CallExpression result ((push $ops)->@*).
    {
        my $result = parse_result('push $ops->@*, $op;');
        ok(defined $result, 'push with postfix deref arg parses without ambiguity');
    }

    # --- Consecutive variable declarations with // ---
    # `my $x = $a // $b // $c;\n my $y = $d // '';` should not be parsed as
    # a single statement where `/ $c;\n my $y = $d /` becomes a regex literal.
    {
        my $result = parse_result("my \$x = \$a // \$b // \$c;\nmy \$y = \$d // '';");
        ok(defined $result, 'consecutive vardecls with // parse without ambiguity');
    }

    # Bare statements at top-level (outside blocks) are rejected because
    # StatementItem requires a semicolon for SimpleStatement. Only Block
    # alt 1 allows a trailing SimpleStatement without semicolon.
    {
        my $result = parse_result('my $x = 42');
        ok(!defined $result, 'bare last statement at EOF is rejected (no semicolon)');
    }
    {
        my $result = parse_result('my $x = 1; my $y = $x + 2');
        ok(!defined $result, 'bare final statement at EOF is rejected (no semicolon)');
    }

    # Block alt 1 allows a trailing SimpleStatement without semicolon.
    # This is needed for anonymous subs like `sub { return $x }` where the
    # last expression omits the trailing semicolon before `}`.
    {
        my $result = parse_result('{ my $x = 42 }');
        ok(defined $result, 'bare last statement in block is accepted (no semicolon before })');
    }
    {
        my $result = parse_result('{ $x; $y }');
        ok(defined $result, 'block with semicolon-terminated stmt + bare last stmt');
    }
    {
        my $result = parse_result('sub { return $ctx };');
        ok(defined $result, 'anon sub with bare return in body');
    }
    {
        my $result = parse_result('sub ($x) { return $x };');
        ok(defined $result, 'anon sub with sig and bare return in body');
    }
    {
        my $result = parse_result('$self->extend(sub ($ctx) { return $ctx });');
        ok(defined $result, 'method call with anon sub arg');
    }

    # --- map/grep as CallExpression: block-first builtins ---
    {
        my $result = parse_result('my @r = map { $_ } @list;');
        ok(defined $result, 'map with block and array parses');
    }
    {
        my $result = parse_result('my %h = map { $_ => 1 } qw(foo bar);');
        ok(defined $result, 'map with fat-comma block and qw list parses');
    }
    {
        my $result = parse_result('my @r = grep { $_ } @items;');
        ok(defined $result, 'grep with block and array parses');
    }

    # --- __SUB__: recursive closure pattern ---
    {
        my $result = parse_result('my $f = sub { __SUB__->($x); };');
        ok(defined $result, '__SUB__->() recursive call parses');
    }

    # --- isa: binary operator ---
    {
        my $result = parse_result('my $r = $x isa q{Foo};');
        ok(defined $result, 'isa binary expression parses');
    }
}

done_testing();
