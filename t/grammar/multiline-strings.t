#!/usr/bin/env perl
# ABOUTME: Test multi-line quoted string parsing
# ABOUTME: Verify QuotedString regex handles newlines correctly
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 3;
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

# Test 1: Single-line eval STRING
my $single = q{eval 'print "hi";';};
ok($parser->parse_string($single), 'single-line eval STRING');

# Test 2: Multi-line eval STRING (the lex.t pattern)
my $multi = q{eval 'while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");
';};

ok($parser->parse_string($multi), 'multi-line eval STRING');

# Test 3: Just a multi-line string (not eval)
my $just_string = q{my $x = 'foo
bar
baz';};

ok($parser->parse_string($just_string), 'multi-line quoted string assignment');
