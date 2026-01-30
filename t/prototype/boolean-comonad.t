# ABOUTME: Test for prototype unified EvalContext comonad architecture
# ABOUTME: Verifies that Parser can create EvalContext and pass to Boolean semiring
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Test::More;
use Chalk::Grammar;
use Chalk::Semiring::Boolean;
use Chalk::Parser;

# Test with a minimal grammar: S -> 'a' 'b'
{
    my $rule = Chalk::GrammarRule->new(
        lhs => 'S',
        rhs => ['a', 'b']
    );

    my $grammar = Chalk::Grammar->new(
        rules => { 'S' => [$rule] },
        start_symbol => 'S'
    );

    my $boolean = Chalk::Semiring::Boolean->new();
    my $parser  = Chalk::Parser->new( grammar => $grammar, semiring => $boolean );

    # Should parse "ab"
    my $result = $parser->parse_string('ab');
    ok( $result, 'Boolean semiring accepts valid parse' );

    # Should reject "a" (incomplete)
    my $result2 = $parser->parse_string('a');
    ok( !$result2, 'Boolean semiring rejects incomplete parse' );

    # Should reject "abc" (extra character)
    my $result3 = $parser->parse_string('abc');
    ok( !$result3, 'Boolean semiring rejects parse with extra input' );
}

# Test 2: Verify context is stored in element
{
    my $rule = Chalk::GrammarRule->new(
        lhs => 'S',
        rhs => ['x']
    );

    my $grammar = Chalk::Grammar->new(
        rules => { 'S' => [$rule] },
        start_symbol => 'S'
    );

    my $boolean = Chalk::Semiring::Boolean->new();
    my $parser  = Chalk::Parser->new( grammar => $grammar, semiring => $boolean );

    my $result = $parser->parse_string('x');
    ok( $result, 'Parse succeeded' );

    # Check if result has context
    ok( defined($result->context), 'Element has context' ) if $result;

    if ($result && defined($result->context)) {
        my $ctx = $result->context;
        is( $ctx->start_pos, 0, 'Context has correct start_pos' );
        ok( defined($ctx->grammar), 'Context has grammar reference' );
        ok( defined($ctx->rule), 'Context has rule reference' );
    }
}

# Test 3: Verify multiply() builds context tree with nonterminals
{
    # Grammar: S -> A B, A -> 'a', B -> 'b'
    my $rule_S = Chalk::GrammarRule->new(
        lhs => 'S',
        rhs => ['A', 'B']
    );
    my $rule_A = Chalk::GrammarRule->new(
        lhs => 'A',
        rhs => ['a']
    );
    my $rule_B = Chalk::GrammarRule->new(
        lhs => 'B',
        rhs => ['b']
    );

    my $grammar = Chalk::Grammar->new(
        rules => {
            'S' => [$rule_S],
            'A' => [$rule_A],
            'B' => [$rule_B]
        },
        start_symbol => 'S'
    );

    my $boolean = Chalk::Semiring::Boolean->new();
    my $parser  = Chalk::Parser->new( grammar => $grammar, semiring => $boolean );

    my $result = $parser->parse_string('ab');
    ok( $result, 'Parse succeeded for sequence with nonterminals' );

    # Check context tree depth
    if ($result && defined($result->context)) {
        my $ctx = $result->context;
        my $children_count = scalar($ctx->children->@*);

        # Debug: show what we got
        if ($ENV{DEBUG_CONTEXT}) {
            warn "Result context: " . $ctx->to_string . "\n";
            warn "Children count: $children_count\n";
            for my $i (0 .. $children_count - 1) {
                my $child = $ctx->children->[$i];
                warn "  Child $i: " . (ref($child) ? $child->to_string : $child) . "\n";
            }
        }

        # Now we should see children since multiply() will be called
        ok( $children_count > 0, "Context has children (count: $children_count)" );
    }
}

done_testing();
