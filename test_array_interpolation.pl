#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my @tests = (
    '@{[1]}',
    '@{[ 1 ]}',
    '@{[ "foo" ]}',
    '@{[ qq{foo} ]}',
    '"text @{[ 1 ]} more"',
    'qq{@{[ qq{foo} ]}}',
);

for my $test (@tests) {
    my $result = $parser->parse_string($test) ? "✓" : "✗";
    say "$result  $test";
}
