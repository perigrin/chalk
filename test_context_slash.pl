#!/usr/bin/env perl
# ABOUTME: Test slash context after closing brace
# ABOUTME: Compare hash subscript vs block closure
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing / context sensitivity:\n";
print "=" x 60 . "\n";

my @tests = (
    # Hash subscript - / should be division
    ['$foo{1} / 1;', 'Hash subscript followed by division'],

    # Block closure - / should start regex (new statement)
    ['while (0) { } /^/;', 'Block closure followed by regex'],

    # The actual failing case from lex.t
    ['while (0) { print "foo\n"; }
/^/ && 1;', 'Multi-line: block then regex statement'],

    # Simpler version
    ['{ } /^/;', 'Bare block followed by regex'],

    # With explicit binding for comparison
    ['{ } $_ =~ /^/;', 'Bare block followed by explicit binding'],
);

for my $test (@tests) {
    my ($code, $desc) = @$test;
    local $SIG{__WARN__} = sub {};
    my $result = eval { $parser->parse_string($code) };
    printf "%-50s %s\n", $desc, $result ? "PASS ✓" : "FAIL ✗";
}
