#!/usr/bin/env perl
# ABOUTME: Test bare regex patterns as statements
# ABOUTME: Issue: lex.t fails because /^/ after } isn't recognized
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 8;
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use Chalk::Parser;
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "..", "grammar", "chalk.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");

my $parser = Chalk::Parser->new(grammar => $chalk_grammar);

TODO: {
    local $TODO = "chalk.bnf doesn't yet support bare regex patterns as statements";

    # Test 1: Simple bare regex with semicolon
    ok($parser->parse_string('/^/;'), 'bare regex with semicolon');

    # Test 2: Bare regex in && expression
    ok($parser->parse_string('/^/ && 1;'), 'bare regex in && expression');

    # Test 3: Bare regex after bare block
    ok($parser->parse_string('{ } /^/;'), 'bare regex after bare block');

    # Test 4: Bare regex after if block
    ok($parser->parse_string('if (1) { } /^/;'), 'bare regex after if block');

    # Test 5: Bare regex after while block
    ok($parser->parse_string('while (0) { } /^/;'), 'bare regex after while block');

    # Test 6: The exact lex.t pattern (simplified)
    ok($parser->parse_string('while (0) { print "x"; }
/^/;'), 'while block then newline then bare regex');

    # Test 7: Ensure bare regex in if condition still works (regression test)
    ok($parser->parse_string('if (/^/) { }'), 'bare regex in if condition (regression)');

    # Test 8: Ensure explicit binding still works (regression test)
    ok($parser->parse_string('$_ =~ /^/;'), 'explicit binding (regression)');
}

done_testing();
