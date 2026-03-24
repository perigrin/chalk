# ABOUTME: Tests for position-independent hash-consing (Component 4, #653).
# ABOUTME: Verifies scan contexts are shared across positions for identical text.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Semiring::TypeInference;

# Test 1: SemanticAction on_scan returns same Context for same text at different positions
# The scan leaf Context for "foo" at position 10 should be the same object as
# "foo" at position 50, since position is bookkeeping, not semantics.
{
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one = $sa->one();

    # Scan "foo" at position 10
    my $ctx1 = $sa->on_scan($one, 'TestRule', 0, 10, 'foo');

    # Scan "foo" at position 50 — should produce the same leaf context
    my $ctx2 = $sa->on_scan($one, 'TestRule', 0, 50, 'foo');

    # The multiply results differ (different left/right refaddrs from one()),
    # but the scan leaf inside should be the same object.
    # Since on_scan returns multiply(one, scan_ctx), and one() returns the same
    # object both times, the multiply should also be the same.
    is(refaddr($ctx1), refaddr($ctx2),
        "on_scan returns same Context for same text at different positions");
}

# Test 2: Different text at same position produces different Contexts
{
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one = $sa->one();

    my $ctx1 = $sa->on_scan($one, 'TestRule', 0, 10, 'foo');
    my $ctx2 = $sa->on_scan($one, 'TestRule', 0, 10, 'bar');

    isnt(refaddr($ctx1), refaddr($ctx2),
        "different text produces different Contexts even at same position");
}

# Test 3: TypeInference on_scan already position-independent (scan level)
{
    my $ti = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => sub { false },
        builtin_lookup => sub { return },
    );
    $ti->reset_cache();

    my $one = $ti->one();

    # Scan same text at two different positions
    my $scan1 = $ti->on_scan($one, 'TestRule', 0, 10, 'foo');
    my $scan2 = $ti->on_scan($one, 'TestRule', 0, 50, 'foo');

    # TypeInference scan contexts are already position-independent
    is(refaddr($scan1), refaddr($scan2),
        "TypeInference on_scan: same value for same text at different positions");
}

# Test 3b: TypeInference _extend_ctx_with_focus position-independence
# Contexts with same focus/children but different positions should hash-cons
# to the same extended context after dropping position from key.
{
    my $ti = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => sub { false },
        builtin_lookup => sub { return },
    );
    $ti->reset_cache();

    # Create two contexts with identical content but different positions
    my $ctx_a = Chalk::Bootstrap::Context->new(
        focus    => { 'type' => 'Str' },
        children => [],
        position => 10,
        rule     => 'TestRule',
    );
    my $ctx_b = Chalk::Bootstrap::Context->new(
        focus    => { 'type' => 'Str' },
        children => [],
        position => 50,
        rule     => 'TestRule',
    );

    # Call _extend_ctx_with_focus on both — should return same refaddr
    # when position is dropped from the key
    my $ext_a = $ti->_extend_ctx_with_focus($ctx_a, { 'type' => 'Int' }, 'WrapRule');
    my $ext_b = $ti->_extend_ctx_with_focus($ctx_b, { 'type' => 'Int' }, 'WrapRule');

    is(refaddr($ext_a), refaddr($ext_b),
        "TypeInference _extend_ctx_with_focus: position-independent hash-consing");
}

# Test 4: Parse correctness — same token at two positions produces correct IR
# Parse "a+a" where "a" appears at positions 0 and 2 — both must remain
# distinct in the parse tree (different positions matter for the tree structure,
# just not for scan leaf identity).
{
    use Chalk::Grammar::Rule;
    use Chalk::Grammar::Symbol;
    use Chalk::Bootstrap::Earley;
    use Chalk::Bootstrap::Semiring::Boolean;

    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Expr',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '\w+'),
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '\+'),
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '\w+'),
            ]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a+a'), "same token at different positions: parses correctly");
    ok($parser->parse('x+y'), "different tokens: parses correctly");
    ok(!$parser->parse('a+'), "incomplete expression: rejects");
}

done_testing;
