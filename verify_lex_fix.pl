#!/usr/bin/env perl
# ABOUTME: Verify that lex.t now parses after PatternMatchStatement fix
# ABOUTME: Run this with Perl 5.42.0 to test the bare regex grammar change
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Verifying lex.t parsing after PatternMatchStatement fix\n";
print "=" x 60 . "\n\n";

# Test 1: Minimal case from lex.t that was failing
print "Test 1: Minimal failing case (while + bare regex)\n";
my $minimal = q{while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");};

local $SIG{__WARN__} = sub {};
my $result1 = $parser->parse_string($minimal);
printf "  Result: %s\n\n", $result1 ? "✓ PASS" : "✗ FAIL";

# Test 2: Just bare regex as statement
print "Test 2: Bare regex as statement\n";
my $bare = '/^/;';
my $result2 = $parser->parse_string($bare);
printf "  Result: %s\n\n", $result2 ? "✓ PASS" : "✗ FAIL";

# Test 3: Bare regex in && expression
print "Test 3: Bare regex in && expression\n";
my $and_expr = '/^/ && 1;';
my $result3 = $parser->parse_string($and_expr);
printf "  Result: %s\n\n", $result3 ? "✓ PASS" : "✗ FAIL";

# Test 4: Full lex.t file
print "Test 4: Full perl-tests/base/lex.t file\n";

open my $fh, '<', 'perl-tests/base/lex.t' or die "Can't open lex.t: $!";
my $code = do { local $/; <$fh> };
close $fh;

printf "  File size: %d bytes\n", length($code);

my $result4 = $parser->parse_string($code);
printf "  Result: %s\n\n", $result4 ? "✓ PASS - lex.t now parses!" : "✗ FAIL - lex.t still has issues";

# Summary
print "=" x 60 . "\n";
my $pass_count = grep { $_ } ($result1, $result2, $result3, $result4);
printf "Summary: %d/4 tests passed\n", $pass_count;

if ($result4) {
    print "\n🎉 SUCCESS! lex.t now parses with the PatternMatchStatement fix!\n";
} elsif ($result1) {
    print "\n⚠️  The minimal case works, but lex.t may have other issues.\n";
} else {
    print "\n❌ The fix didn't resolve the bare regex issue.\n";
}
