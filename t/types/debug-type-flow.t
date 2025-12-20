#!/usr/bin/env perl
# ABOUTME: Debug test to understand type flow through TypeInference semiring
# ABOUTME: Tests if String literals get Str type and if ArithmeticOp sees them

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::TypeInference;

# Load Chalk grammar
open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

subtest 'String literal gets Str type' => sub {
    my $code = '"hello";';

    my $sr = Chalk::Semiring::TypeInference->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sr
    );

    my $result = $parser->parse_string($code);

    ok($result, 'Parse succeeds');

    my $type_name = $result->type_obj->name();
    note("Result type: $type_name");

    # The result should be Str (or at least not Any)
    ok($type_name ne 'Any', 'String literal does not have Any type');
};

subtest 'Addition expression type elements' => sub {
    my $code = '"hello" + "world";';

    my $sr = Chalk::Semiring::TypeInference->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sr
    );

    my $result = $parser->parse_string($code);

    ok($result, 'Parse succeeds');

    my $type_name = $result->type_obj->name();
    note("Result type: $type_name");
    note("Has errors: ", $result->has_errors() ? "yes" : "no");
    note("Valid: ", $result->valid() ? "yes" : "no");

    if ($result->has_errors()) {
        note("Errors:");
        note($result->format_errors($code));
    }

    # Let's inspect the children
    if ($result->can('children')) {
        my @children = $result->children->@*;
        note("Number of children: ", scalar(@children));

        for my $i (0 .. $#children) {
            my $child = $children[$i];
            if ($child->can('type_obj')) {
                note("  Child $i type: ", $child->type_obj->name());
            }
            if ($child->can('token') && defined $child->token) {
                note("  Child $i token: ", $child->token);
            }
        }
    }
};
