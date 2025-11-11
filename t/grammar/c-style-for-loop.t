#!/usr/bin/env perl
# ABOUTME: Test C-style for loop parsing
# ABOUTME: Verify for (init; condition; increment) syntax is supported
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 5;
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use Chalk::Parser;
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "grammar", "perl.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");

my $parser = Chalk::Parser->new(grammar => $chalk_grammar);

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

# C-style for loops
ok($parser->parse_string('for (my $i = 0; $i < 10; $i++) {}'),
   'C-style for with my');
ok($parser->parse_string('for ($i = 0; $i < 10; $i++) {}'),
   'C-style for without my');
ok($parser->parse_string('for (my $i = 0; $i < @lines; $i++) {}'),
   'C-style for with array length');

# Foreach style (should already work)
ok($parser->parse_string('for my $i (0..9) {}'),
   'foreach style');
ok($parser->parse_string('foreach my $line (@lines) {}'),
   'foreach with array');
