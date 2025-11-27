#!/usr/bin/env perl
# ABOUTME: Debug script to find why ChalkSyntax with TypeInference hangs
# ABOUTME: Tests with timeout and progress logging

use 5.42.0;
use FindBin qw($RealBin);
use lib "$RealBin/lib";

# Enable debugging
$ENV{DEBUG_CHALKSYNTAX} = 1;

use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::ChalkSyntax;

# Load grammar
print "Loading grammar...\n";
open my $fh, '<:utf8', "$RealBin/grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');
print "Grammar loaded.\n";

# Create ChalkSyntax semiring
print "Creating ChalkSyntax semiring...\n";
my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
print "Semiring created.\n";

# Test with simplest possible code first
my @test_cases = (
    'return 1;',
    'my $x = 1;',
    'my $x = 1; return $x;',
);

for my $code (@test_cases) {
    print "\n--- Testing: '$code' ---\n";

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    # Set alarm for timeout
    local $SIG{ALRM} = sub { die "TIMEOUT after 10 seconds\n" };
    alarm(10);

    my $result = eval { $parser->parse_string($code) };
    my $error = $@;

    alarm(0);  # Cancel alarm

    if ($error) {
        print "ERROR: $error\n";
        last if $error =~ /TIMEOUT/;
    } elsif ($result) {
        print "SUCCESS: Parsed successfully\n";
    } else {
        print "FAILED: Parse returned false\n";
    }
}

print "\nDebug script complete.\n";
