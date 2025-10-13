#!/usr/bin/env perl
# ABOUTME: Quick test if pat.t parses
# ABOUTME: Verify bare regex in if works
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

open my $fh, '<', 'perl-tests/base/pat.t' or die $!;
my $code = do { local $/; <$fh> };
close $fh;

local $SIG{__WARN__} = sub {};
my $result = $parser->parse_string($code);

print "pat.t parsing: ", $result ? "PASS ✓\n" : "FAIL ✗\n";

# Now test specific contexts
print "\nTesting specific contexts:\n";
print "=" x 60 . "\n";

my @tests = (
    ['if (/^test/) { }', 'Bare regex in if condition'],
    ['while (/^test/) { }', 'Bare regex in while condition'],
    ['{ } /^test/;', 'Bare regex after bare block'],
    ['/^test/;', 'Bare regex as statement'],
    ['/^test/ && 1;', 'Bare regex in && expression'],
);

for my $test (@tests) {
    my ($code, $desc) = @$test;
    my $r = $parser->parse_string($code);
    printf "%-40s %s\n", $desc, $r ? "PASS ✓" : "FAIL ✗";
}
