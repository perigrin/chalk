#!/usr/bin/env perl
# ABOUTME: Test s/// operator parsing
# ABOUTME: Simple test to verify substitution operator patterns work
use 5.40.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my @tests = (
    's|::|/|g',         # Pipe delimiter
    's/::/\//g',        # Slash delimiter
    's!pattern!replacement!gi',  # Bang delimiter
    's#foo#bar#',       # Hash delimiter
    '(my $x = "Foo::Bar") =~ s|::|/|g',  # Full expression
);

for my $code (@tests) {
    my $result = $parser->parse_string($code);
    printf "%-40s %s\n", $code, $result ? "PASS ✓" : "FAIL ✗";
}
