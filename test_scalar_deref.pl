#!/usr/bin/env perl
use 5.040;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my @tests = (
    '$x = 1;',           # basic scalar
    '$$x = 1;',          # scalar deref $$x
    '${$x} = 1;',        # scalar deref ${$x}
    '${ $x } = 1;',      # scalar deref with space
    '$ {$x} = 1;',       # scalar deref with space before brace
    '${x} = 1;',         # looks like scalar deref but x is bareword
    '$CX = 1;',          # named scalar
    '${CX} = 1;',        # deref with bareword
    '$ {CX} = 1;',       # deref with space and bareword
);

say "Testing scalar dereference syntax:\n";
for my $i (0..$#tests) {
    my $result = $parser->parse_string($tests[$i]) ? "✓ PASS" : "✗ FAIL";
    printf "%s  Test %d: %s\n", $result, $i+1, $tests[$i];
}
