#!/usr/bin/env perl
# ABOUTME: BNF parser feature tests - validates semantic actions parser functionality
# ABOUTME: Tests various BNF features: terminals, nonterminals, comments, escape sequences, etc.

use 5.42.0;
use warnings;
use Test::More;

use lib 'lib';
use Chalk::BNF;
use Chalk::Grammar;

# Helper to compare Grammar objects
sub grammars_equivalent {
    my ($grammar1, $grammar2, $test_name) = @_;

    # Both should be Grammar objects
    isa_ok($grammar1, 'Chalk::Grammar', "$test_name - grammar1 is Chalk::Grammar");
    isa_ok($grammar2, 'Chalk::Grammar', "$test_name - grammar2 is Chalk::Grammar");

    # Same start symbol
    is($grammar1->start_symbol, $grammar2->start_symbol,
       "$test_name - start symbols match");

    # Get all nonterminals from both grammars
    my %nonterminals1 = %{$grammar1->rules};
    my %nonterminals2 = %{$grammar2->rules};

    # Same set of nonterminals
    my @keys1 = sort keys %nonterminals1;
    my @keys2 = sort keys %nonterminals2;
    is_deeply(\@keys1, \@keys2,
              "$test_name - same nonterminals");

    # For each nonterminal, compare rules
    for my $lhs (@keys1) {
        my @rules1 = @{$nonterminals1{$lhs}};
        my @rules2 = @{$nonterminals2{$lhs}};

        is(scalar(@rules1), scalar(@rules2),
           "$test_name - $lhs has same number of rules");

        # Compare each rule's RHS
        for my $i (0..$#rules1) {
            my @rhs1 = @{$rules1[$i]->rhs};
            my @rhs2 = @{$rules2[$i]->rhs};

            is_deeply(\@rhs1, \@rhs2,
                     "$test_name - $lhs rule $i RHS matches");
        }
    }
}

# Test 1: Simple single-rule grammar
{
    my $bnf = "Foo -> 'bar'\n";

    my $old_grammar = Chalk::BNF::build_chalk_grammar($bnf);
    my $new_grammar = Chalk::BNF::parse_with_semantic_actions($bnf);

    grammars_equivalent($old_grammar, $new_grammar, "Simple rule");
}

# Test 2: Multiple rules for same nonterminal
{
    my $bnf = <<'EOF';
Expr -> Term
Expr -> Expr '+' Term
Term -> 'number'
EOF

    my $old_grammar = Chalk::BNF::build_chalk_grammar($bnf, 'Expr');
    my $new_grammar = Chalk::BNF::parse_with_semantic_actions($bnf);

    grammars_equivalent($old_grammar, $new_grammar, "Multiple rules");
}

# Test 3: Empty production
{
    my $bnf = <<'EOF';
OptionalComma ->
OptionalComma -> ','
EOF

    my $old_grammar = Chalk::BNF::build_chalk_grammar($bnf, 'OptionalComma');
    my $new_grammar = Chalk::BNF::parse_with_semantic_actions($bnf);

    grammars_equivalent($old_grammar, $new_grammar, "Empty production");
}

# Test 4: Mixed terminals and nonterminals
{
    my $bnf = <<'EOF';
Rule -> 'foo' Bar 'baz'
Bar -> 'x'
EOF

    my $old_grammar = Chalk::BNF::build_chalk_grammar($bnf, 'Rule');
    my $new_grammar = Chalk::BNF::parse_with_semantic_actions($bnf);

    grammars_equivalent($old_grammar, $new_grammar, "Mixed terminals/nonterminals");
}

# Test 5: Full-line comments (should be ignored by both parsers)
{
    my $bnf = <<'EOF';
# This is a comment
Foo -> 'bar'
# Another comment
Baz -> 'qux'
EOF

    my $old_grammar = Chalk::BNF::build_chalk_grammar($bnf);
    my $new_grammar = Chalk::BNF::parse_with_semantic_actions($bnf);

    grammars_equivalent($old_grammar, $new_grammar, "Full-line comments");
}

# Test 6: Inline comments
{
    my $bnf = <<'EOF';
Foo -> 'bar'  # inline comment
Baz -> 'qux'
EOF

    my $old_grammar = Chalk::BNF::build_chalk_grammar($bnf);
    my $new_grammar = Chalk::BNF::parse_with_semantic_actions($bnf);

    grammars_equivalent($old_grammar, $new_grammar, "Inline comments");
}

# Test 7: Parse grammar/bnf.bnf with both approaches
{
    open my $fh, '<', 'grammar/bnf.bnf' or die "Cannot open grammar/bnf.bnf: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    my $old_grammar = Chalk::BNF::build_chalk_grammar($content, 'Grammar');
    my $new_grammar = Chalk::BNF::parse_with_semantic_actions($content);

    ok($old_grammar, "Old parser handles bnf.bnf");
    ok($new_grammar, "New parser handles bnf.bnf");

    if ($old_grammar && $new_grammar) {
        grammars_equivalent($old_grammar, $new_grammar, "bnf.bnf");
    }
}

done_testing();
