#!/usr/bin/env perl
# ABOUTME: Minimal test case for bare regex issue
# ABOUTME: Tests the specific lex.t failure pattern
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing minimal bare regex cases:\n";
print "=" x 60 . "\n";

my @tests = (
    # These should all work in Perl
    ['/^/;', 'Single bare regex with semicolon'],
    ['/^/ && 1;', 'Bare regex in && with semicolon'],
    ['{ } /^/;', 'After bare block'],
    ['if (1) { } /^/;', 'After if block'],
    ['while (0) { } /^/;', 'After while block'],

    # The exact pattern from lex.t (simplified)
    ['while (0) { print "x"; }
/^/;', 'While block, newline, bare regex'],

    # For comparison - these DO work
    ['if (/^/) { }', 'Bare regex in if condition'],
    ['$_ =~ /^/;', 'Explicit binding'],
);

for my $test (@tests) {
    my ($code, $desc) = @$test;
    local $SIG{__WARN__} = sub {};
    my $result = eval { $parser->parse_string($code) };
    my $status = $result ? "✓ PASS" : "✗ FAIL";
    printf "%-45s %s\n", $desc, $status;

    # Show where parsing stopped if it failed
    if (!$result) {
        my $pos = length($code);  # Would need parser state to get exact position
        my $first_20 = substr($code, 0, 20);
        $first_20 =~ s/\n/\\n/g;
        print "   Code: $first_20" . (length($code) > 20 ? "..." : "") . "\n";
    }
}
