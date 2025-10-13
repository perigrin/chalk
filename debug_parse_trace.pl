#!/usr/bin/env perl
# ABOUTME: Debug parsing to understand exactly where/why $x->f($y->z) fails
# ABOUTME: Uses internal parser state inspection to trace the failure
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Semiring::Boolean;

my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new()
);

my @tests = (
    '$a->b($c->d)',
    '$a->b($c->d,)',
);

foreach my $code (@tests) {
    print "=" x 60, "\n";
    print "Testing: $code\n";
    print "=" x 60, "\n";

    my $result = $parser->parse_string($code);
    print "Result: ", $result ? "PASS" : "FAIL", "\n\n";
}
