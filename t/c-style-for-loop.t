#!/usr/bin/env perl
# ABOUTME: Test C-style for loop parsing
# ABOUTME: Verify for (init; condition; increment) syntax is supported
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 5;
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

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
