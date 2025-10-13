#!/usr/bin/env perl
# ABOUTME: Quick test to see if lex.t now parses
# ABOUTME: Tests the bare regex fix
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing if lex.t now parses:\n";
print "=" x 60 . "\n";

# Test the specific failing pattern from lex.t
my $test_code = q{eval 'while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");
';};

print "Test: eval with while block followed by bare regex\n";
local $SIG{__WARN__} = sub {};
my $result = $parser->parse_string($test_code);
print "Result: ", $result ? "PASS ✓\n" : "FAIL ✗\n";

if ($result) {
    print "\n✓ Fix successful! Now testing full lex.t file...\n\n";

    open my $fh, '<', 'perl-tests/base/lex.t' or die $!;
    my $code = do { local $/; <$fh> };
    close $fh;

    my $full_result = $parser->parse_string($code);
    print "Full lex.t: ", $full_result ? "PASS ✓" : "FAIL ✗", "\n";
} else {
    print "\n✗ Fix didn't work for the minimal case\n";
}
