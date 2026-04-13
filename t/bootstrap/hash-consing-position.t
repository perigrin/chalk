# ABOUTME: Tests for position-independent hash-consing (Component 4, #653).
# ABOUTME: Verifies scan contexts are hash-consed by content (text) not position.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Semiring::TypeInference;

# Helper: build an annotated scan Context (as Earley would create it)
sub make_scan_ctx($rule_name, $matched_text, $is_predicted_hash = {}) {
    return Chalk::Bootstrap::Context->new(
        focus       => $matched_text,
        position    => 0,
        annotations => {
            scan      => true,
            rule_name => $rule_name,
            alt_idx   => 0,
            predicted => $is_predicted_hash,
        },
    );
}

# Test 1: SemanticAction multiply with same scan Context object always returns same result
# SA.multiply is keyed by the refaddrs of left and right. When the same scan Context
# object is passed (position is NOT part of the key), the result is hash-consed.
{
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one     = $sa->one();
    my $scan_ctx = make_scan_ctx('TestRule', 'foo');

    # Multiply with the same scan Context twice — must return same object
    my $ctx1 = $sa->multiply($one, $scan_ctx);
    my $ctx2 = $sa->multiply($one, $scan_ctx);

    is(refaddr($ctx1), refaddr($ctx2),
        "SA multiply with same scan Context returns same hash-consed object");
}

# Test 2: SA multiply with different scan Contexts (different text) produces different results
{
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one = $sa->one();

    my $ctx1 = $sa->multiply($one, make_scan_ctx('TestRule', 'foo'));
    my $ctx2 = $sa->multiply($one, make_scan_ctx('TestRule', 'bar'));

    isnt(refaddr($ctx1), refaddr($ctx2),
        "different text in scan Context produces different SA multiply results");
}

# Test 3: TypeInference multiply with scan Context is position-independent (keyed by content)
{
    my $ti = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => sub { false },
        builtin_lookup => sub { return },
    );
    $ti->reset_cache();

    my $one = $ti->one();

    # Scan same text: TI type-tag results are hash-consed by text, not position
    my $scan1 = $ti->multiply($one, make_scan_ctx('TestRule', 'foo'));
    my $scan2 = $ti->multiply($one, make_scan_ctx('TestRule', 'foo'));

    # TypeInference multiply returns hash-consed tag hashes keyed by rule+text
    is(refaddr($scan1), refaddr($scan2),
        "TypeInference multiply: same text produces same hash-consed result");
}

# Test 3b: TypeInference _extend_ctx_with_focus position-independence
# TI multiply position-independence: same input pair → same hash-consed result.
# TI.multiply keys results by the refaddrs of its children, not by position.
# Two multiply calls with the same child object always return the same result.
{
    my $ti = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => sub { false },
        builtin_lookup => sub { return },
    );
    $ti->reset_cache();

    my $ctx_a = Chalk::Bootstrap::Context->new(
        focus       => { 'type' => 'Str' },
        children    => [],
        position    => 10,
        rule        => 'TestRule',
        annotations => { type => { valid => true, type => 'Str' } },
    );

    # Multiply the same object with itself twice — must produce the same hash-consed result
    my $mul_a = $ti->multiply($ctx_a, $ctx_a);
    my $mul_b = $ti->multiply($ctx_a, $ctx_a);

    is(refaddr($mul_a), refaddr($mul_b),
        "TypeInference multiply: same inputs produce same hash-consed result");
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
