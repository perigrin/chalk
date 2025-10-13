#!/usr/bin/env perl
# ABOUTME: Debug script to test arrow method call parsing
# ABOUTME: Tests minimal case of $x->multiply($y->z)
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Preprocessor::Heredoc;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Test cases
my @tests = (
    'foo($y->z)',                   # Plain function - PASS
    'Foo::bar($y->z)',              # Qualified function - test
    '$x->multiply($y->z)',          # Arrow method - FAIL (we know this)
    '$x->multiply($y->z, $a)',      # Arrow method with 2 params - test
    '$x->multiply($a, $y->z)',      # Arrow in 2nd param - test
);

foreach my $test (@tests) {
    print "\n" . "=" x 60 . "\n";
    print "Testing: $test\n";
    print "=" x 60 . "\n";

    my $result = $parser->parse_string($test);

    if ($result) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        print "Parsed: " . ($parser->{last_position} // 0) . " / " . length($test) . " chars\n";
        my $pos = $parser->{last_position} // 0;
        if ($pos > 0 && $pos < length($test)) {
            print "Stopped at: '" . substr($test, $pos, 1) . "'\n";
            print "Before: '" . substr($test, 0, $pos) . "'\n";
            print "After: '" . substr($test, $pos) . "'\n";
        }
    }
}
