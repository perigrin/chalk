#!/usr/bin/env perl
# ABOUTME: Test eval STRING vs eval BLOCK parsing
# ABOUTME: Ensures both forms of eval are handled correctly
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 5;
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

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

# Test 1: Code without eval (bare regex works)
my $no_eval = q{while (0) {
    print "foo\n";
}
/^/ && (print "ok\n");};

ok($parser->parse_string($no_eval), 'no eval wrapper');

# Test 2: eval BLOCK (should work - it\'s like a subroutine)
my $eval_block = q{eval {
    while (0) {
        print "foo\n";
    }
    /^/ && (print "ok\n");
};};

ok($parser->parse_string($eval_block), 'eval BLOCK {}');

# Test 3: eval STRING (the lex.t pattern)
my $eval_string = q{eval 'while (0) {
    print "foo\n";
}
/^/ && (print "ok\n");
';};

ok($parser->parse_string($eval_string), 'eval STRING with complex code');

# Test 4: Simple eval STRING
my $simple_eval = q{eval 'print "hi";';};

ok($parser->parse_string($simple_eval), 'simple eval STRING');

# Test 5: eval with builtin function call
my $eval_builtin = q{eval 'print 1+1;';};

ok($parser->parse_string($eval_builtin), 'eval STRING with expression');
