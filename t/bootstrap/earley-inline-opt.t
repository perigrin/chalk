# ABOUTME: Tests for ? quantifier handling in the Earley parser via DFA nullable prediction.
# ABOUTME: Verifies DFA includes dot-advanced items for nullable symbols, and parses produce correct results.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Desugar;
use Chalk::Bootstrap::CoreItemIndex;
use Chalk::Bootstrap::LR0DFA;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Helper to create terminal symbol
sub terminal($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => $value,
    );
}

# Helper to create reference symbol (nonterminal)
sub reference($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'reference',
        value => $value,
    );
}

# Helper to create quantified reference symbol
sub opt_reference($value) {
    return Chalk::Grammar::Symbol->new(
        type       => 'reference',
        value      => $value,
        quantifier => '?',
    );
}

# Test 1: Grammar with ? quantifier — optional present
# Start ::= 'a' B? 'c'
# B     ::= 'b'
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B'), terminal('c')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('abc'), "optional present: accepts 'abc'");
}

# Test 2: Grammar with ? quantifier — optional absent
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B'), terminal('c')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ac'), "optional absent: accepts 'ac'");
}

# Test 3: Grammar with ? quantifier — rejection still works
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B'), terminal('c')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok(!$parser->parse('a'), "rejects incomplete 'a'");
    ok(!$parser->parse('ab'), "rejects incomplete 'ab'");
    ok(!$parser->parse('bc'), "rejects 'bc' (missing required 'a')");
    ok(!$parser->parse('abbc'), "rejects 'abbc' (B is optional, not repeatable)");
}

# Test 4: ? at end of rule
# Start ::= 'a' B?
# B     ::= 'b'
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ab'), "optional at end present: accepts 'ab'");
    ok($parser->parse('a'), "optional at end absent: accepts 'a'");
    ok(!$parser->parse('b'), "rejects 'b'");
}

# Test 5: ? at start of rule
# Start ::= B? 'a'
# B     ::= 'b'
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[opt_reference('B'), terminal('a')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ba'), "optional at start present: accepts 'ba'");
    ok($parser->parse('a'), "optional at start absent: accepts 'a'");
    ok(!$parser->parse('b'), "rejects 'b'");
}

# Test 6: Multiple optionals in one rule
# Start ::= A? 'x' B?
# A     ::= 'a'
# B     ::= 'b'
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[opt_reference('A'), terminal('x'), opt_reference('B')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[terminal('a')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('axb'), "both optionals present: accepts 'axb'");
    ok($parser->parse('ax'), "only A present: accepts 'ax'");
    ok($parser->parse('xb'), "only B present: accepts 'xb'");
    ok($parser->parse('x'), "both absent: accepts 'x'");
    ok(!$parser->parse('ab'), "rejects 'ab' (missing 'x')");
}

# Test 7: Desugar.pm no longer creates _opt helper rules for ?
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B'), terminal('c')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($grammar);

    # Should have exactly 2 rules (Start + B), no B_opt helper
    is(scalar $desugared->@*, 2, "desugar does not create _opt helper for ? quantifier");

    # The ? symbol should still be in the desugared grammar (pass-through)
    my $start = $desugared->[0];
    my $sym = $start->expressions()->[0][1];
    ok($sym->is_quantified(), "? symbol preserved in desugared grammar");
    is($sym->quantifier(), '?', "quantifier is still '?'");
}

# Test 8: SemanticAction produces correct Context tree with placeholder for absent optional
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a'), opt_reference('B'), terminal('c')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    # Optional absent: 'ac'
    my $value = $parser->parse_value('ac');
    ok(defined $value, "SemanticAction parse_value returns defined for 'ac'");

    # The context should have children for: 'a', placeholder, 'c'
    # The placeholder represents the absent B?
    my @children = $value->children()->@*;
    # Flatten the multiply tree to count significant leaves (non-one() singletons)
    my @leaves;
    my $collect;
    $collect = sub($ctx) {
        if ($ctx->children()->@* == 0) {
            push @leaves, $ctx;
        } else {
            for my $child ($ctx->children()->@*) {
                $collect->($child);
            }
        }
    };
    $collect->($value);
    # Filter out the one() singleton: it has undef focus, no rule, no children
    my @significant = grep {
        defined $_->extract() || defined $_->rule()
    } @leaves;
    # We expect 3 significant leaves: 'a' scan, placeholder (B_opt rule), 'c' scan
    is(scalar @significant, 3,
        "absent optional produces 3 significant leaf contexts (a, placeholder, c)");
    is($significant[0]->extract(), 'a', "first leaf is 'a'");
    ok(!defined $significant[1]->extract(), "second leaf (placeholder) has undef focus");
    is($significant[1]->rule(), 'B_opt', "placeholder has B_opt rule name");
    is($significant[2]->extract(), 'c', "third leaf is 'c'");

    # Optional present: 'abc'
    my $value2 = $parser->parse_value('abc');
    $semiring->reset_cache();
    ok(defined $value2, "SemanticAction parse_value returns defined for 'abc'");
}

# Test 9: DFA prediction items include dot>0 for rules with ? at start
# Start ::= B? 'a'
# B     ::= 'b'
# When predicting Start, the DFA should include:
#   - Start:0:0 (dot before B?)
#   - Start:0:1 (dot after B?, skipping it)
#   - B:0:0 (transitively predicted from B?)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[opt_reference('B'), terminal('a')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($grammar);

    my $core_index = Chalk::Bootstrap::CoreItemIndex->new();
    $core_index->build_from_grammar($desugared);

    my %rule_table = map { $_->name() => $_ } $desugared->@*;

    my $dfa = Chalk::Bootstrap::LR0DFA->new(
        grammar    => $desugared,
        core_index => $core_index,
        rule_table => \%rule_table,
    );
    $dfa->build();

    my $pred_items = $dfa->prediction_items_for('Start');
    ok(defined $pred_items, "DFA has prediction items for Start");

    # Extract core IDs from prediction items
    # After DFA nullable optimization, items are [$core_id, $skip_symbols] pairs
    my @core_ids = map { ref($_) eq 'ARRAY' ? $_->[0] : $_ } $pred_items->@*;

    # Should include Start:0:0 (dot=0) and Start:0:1 (dot=1, skipped B?)
    my $start_dot0 = $core_index->id_for('Start', 0, 0);
    my $start_dot1 = $core_index->id_for('Start', 0, 1);
    my $b_dot0     = $core_index->id_for('B', 0, 0);

    ok((grep { $_ == $start_dot0 } @core_ids), "DFA includes Start:0:0 in prediction");
    ok((grep { $_ == $start_dot1 } @core_ids), "DFA includes Start:0:1 (skip B?) in prediction");
    ok((grep { $_ == $b_dot0 } @core_ids), "DFA includes B:0:0 (transitive from B?) in prediction");
}

# Test 10: DFA detects nullable nonterminals from * desugaring
# Grammar: Start ::= A* 'x'
# After desugaring: Start ::= A_star 'x', A_star ::= A A_star | ε
# A_star is nullable (has empty alternative), so DFA should include Start:0:1
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[
                Chalk::Grammar::Symbol->new(
                    type       => 'reference',
                    value      => 'A',
                    quantifier => '*',
                ),
                terminal('x'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[terminal('a')]],
        ),
    ];

    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($grammar);

    my $core_index = Chalk::Bootstrap::CoreItemIndex->new();
    $core_index->build_from_grammar($desugared);

    my %rule_table = map { $_->name() => $_ } $desugared->@*;

    my $dfa = Chalk::Bootstrap::LR0DFA->new(
        grammar    => $desugared,
        core_index => $core_index,
        rule_table => \%rule_table,
    );
    $dfa->build();

    # Check that DFA exposes nullable_set (or that prediction items reflect it)
    my $pred_items = $dfa->prediction_items_for('Start');
    ok(defined $pred_items, "DFA has prediction items for Start with * grammar");

    my @core_ids = map { ref($_) eq 'ARRAY' ? $_->[0] : $_ } $pred_items->@*;

    # A_star is nullable (has epsilon alternative). So Start:0:1 should be in prediction set.
    my $start_dot0 = $core_index->id_for('Start', 0, 0);
    my $start_dot1 = $core_index->id_for('Start', 0, 1);

    ok((grep { $_ == $start_dot0 } @core_ids), "DFA includes Start:0:0 for * grammar");
    ok((grep { $_ == $start_dot1 } @core_ids),
        "DFA includes Start:0:1 (skip nullable A_star) in prediction");
}

# Test 11: DFA prediction items for chained optionals include dot=2
# Start ::= A? B? 'x'
# DFA should include Start:0:0, Start:0:1 (skip A?), Start:0:2 (skip A? and B?)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[opt_reference('A'), opt_reference('B'), terminal('x')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[terminal('a')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($grammar);

    my $core_index = Chalk::Bootstrap::CoreItemIndex->new();
    $core_index->build_from_grammar($desugared);

    my %rule_table = map { $_->name() => $_ } $desugared->@*;

    my $dfa = Chalk::Bootstrap::LR0DFA->new(
        grammar    => $desugared,
        core_index => $core_index,
        rule_table => \%rule_table,
    );
    $dfa->build();

    my $pred_items = $dfa->prediction_items_for('Start');
    my @core_ids = map { ref($_) eq 'ARRAY' ? $_->[0] : $_ } $pred_items->@*;

    my $start_dot0 = $core_index->id_for('Start', 0, 0);
    my $start_dot1 = $core_index->id_for('Start', 0, 1);
    my $start_dot2 = $core_index->id_for('Start', 0, 2);

    ok((grep { $_ == $start_dot0 } @core_ids), "chained: DFA includes Start:0:0");
    ok((grep { $_ == $start_dot1 } @core_ids), "chained: DFA includes Start:0:1 (skip A?)");
    ok((grep { $_ == $start_dot2 } @core_ids), "chained: DFA includes Start:0:2 (skip A? B?)");
}

# Test 12: DFA skip metadata tracks ? symbol names
# Start ::= B? 'a'
# The dot=1 prediction item for Start should carry skip metadata ['B']
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[opt_reference('B'), terminal('a')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
    ];

    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($grammar);

    my $core_index = Chalk::Bootstrap::CoreItemIndex->new();
    $core_index->build_from_grammar($desugared);

    my %rule_table = map { $_->name() => $_ } $desugared->@*;

    my $dfa = Chalk::Bootstrap::LR0DFA->new(
        grammar    => $desugared,
        core_index => $core_index,
        rule_table => \%rule_table,
    );
    $dfa->build();

    my $pred_items = $dfa->prediction_items_for('Start');
    my $start_dot1 = $core_index->id_for('Start', 0, 1);

    # Find the dot=1 item and check its skip metadata
    my $found_skip;
    for my $entry ($pred_items->@*) {
        if (ref($entry) eq 'ARRAY' && $entry->[0] == $start_dot1) {
            $found_skip = $entry->[1];
            last;
        }
    }
    ok(defined $found_skip, "dot=1 item has skip metadata");
    is(ref($found_skip), 'ARRAY', "skip metadata is arrayref");
    is(scalar $found_skip->@*, 1, "skip metadata has one entry");
    is($found_skip->[0], 'B', "skip metadata records skipped symbol 'B'");
}

done_testing;
