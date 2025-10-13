#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

# The transformed output from our preprocessor
my $code = q{print qq{@{[ qq{foo} ]}}};

say "Testing: $code";
say "Result: ", $parser->parse_string($code) ? "✓ PASS" : "✗ FAIL";

# What our grammar actually sees
say "\nOur regex matches: [anything except }]";
say "This will match up to the FIRST } it sees!";

# Simulate our grammar's regex
if ($code =~ /qq\s*\{[^}]*\}/) {
    say "Matched: '$&'";
    say "This only captured the content up to first }";
}
