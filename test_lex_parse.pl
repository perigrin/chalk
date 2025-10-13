#!/usr/bin/env perl
# ABOUTME: Test if lex.t now parses after bare regex fix
# ABOUTME: Verifies PatternMatchStatement grammar change
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing lex.t parsing after PatternMatchStatement fix\n";
print "=" x 60 . "\n";

# First test the minimal failing case
print "\n1. Testing minimal case: while block + bare regex\n";
my $minimal = q{while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");};

local $SIG{__WARN__} = sub {};
my $result = $parser->parse_string($minimal);
print "   Result: ", $result ? "✓ PASS" : "✗ FAIL", "\n";

# Now test the full lex.t file
print "\n2. Testing full perl-tests/base/lex.t\n";

open my $fh, '<', 'perl-tests/base/lex.t' or die "Can't open lex.t: $!";
my $code = do { local $/; <$fh> };
close $fh;

my $len = length($code);
print "   File size: $len bytes\n";

my $full_result = $parser->parse_string($code);

if ($full_result) {
    print "   Result: ✓ PASS - lex.t now parses successfully!\n";
} else {
    print "   Result: ✗ FAIL - lex.t still doesn't parse\n";
    print "   (Parser may have stopped at a different issue)\n";
}

print "\n" . "=" x 60 . "\n";
print $full_result ? "SUCCESS!" : "NEEDS MORE WORK";
print "\n";
