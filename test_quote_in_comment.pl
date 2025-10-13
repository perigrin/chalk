#!/usr/bin/env perl
# ABOUTME: Test if quotes in comments confuse the parser
# ABOUTME: Check line 18 from lex.t which has # '; pattern
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing quotes in comments\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

# Test 1: Simple comment with quote
my $simple = q{my $x = 1; # '};
print "Test 1: Comment ending with quote\n";
my $r1 = $parser->parse_string($simple);
printf "  Result: %s\n\n", $r1 ? "PASS ✓" : "FAIL ✗";

# Test 2: The exact line 18 pattern from lex.t
my $line18 = q{$x = '\\'; # ';};
print "Test 2: Line 18 from lex.t\n";
my $r2 = $parser->parse_string($line18);
printf "  Result: %s\n\n", $r2 ? "PASS ✓" : "FAIL ✗";

# Test 3: Line 18 + blank line + eval
my $with_eval = q{$x = '\\'; # ';

eval 'print "hi";';};
print "Test 3: Line 18 + blank line + eval\n";
my $r3 = $parser->parse_string($with_eval);
printf "  Result: %s\n\n", $r3 ? "PASS ✓" : "FAIL ✗";

# Test 4: Line 18 + if statement + eval (like lex.t)
my $full_context = q{$x = '\\'; # ';

if (length($x) == 1) {print "ok 4\n";} else {print "not ok 4\n";}

eval 'while (0) {
    print "foo\n";
}
/^/ && (print "ok 5\n");
';};

print "Test 4: Lines 18-26 from lex.t\n";
my $r4 = $parser->parse_string($full_context);
printf "  Result: %s\n\n", $r4 ? "PASS ✓" : "FAIL ✗";

print "=" x 60 . "\n";
my $pass_count = grep { $_ } ($r1, $r2, $r3, $r4);
printf "Summary: %d/4 tests passed\n", $pass_count;
