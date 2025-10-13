#!/usr/bin/env perl
# ABOUTME: Test if eval STRING is the problem
# ABOUTME: Compare eval BLOCK vs eval STRING
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

print "Testing eval BLOCK vs eval STRING\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

# Test 1: Code without eval (bare regex works)
my $no_eval = q{while (0) {
    print "foo\n";
}
/^/ && (print "ok\n");};

print "Test 1: No eval wrapper\n";
my $r1 = $parser->parse_string($no_eval);
printf "  Result: %s\n\n", $r1 ? "PASS ✓" : "FAIL ✗";

# Test 2: eval BLOCK (should work - it's like a subroutine)
my $eval_block = q{eval {
    while (0) {
        print "foo\n";
    }
    /^/ && (print "ok\n");
};};

print "Test 2: eval BLOCK {}\n";
my $r2 = $parser->parse_string($eval_block);
printf "  Result: %s\n\n", $r2 ? "PASS ✓" : "FAIL ✗";

# Test 3: eval STRING (the lex.t pattern)
my $eval_string = q{eval 'while (0) {
    print "foo\n";
}
/^/ && (print "ok\n");
';};

print "Test 3: eval STRING '...'\n";
my $r3 = $parser->parse_string($eval_string);
printf "  Result: %s\n\n", $r3 ? "PASS ✓" : "FAIL ✗";

# Test 4: Simple eval STRING
my $simple_eval = q{eval 'print "hi";';};

print "Test 4: Simple eval STRING\n";
my $r4 = $parser->parse_string($simple_eval);
printf "  Result: %s\n\n", $r4 ? "PASS ✓" : "FAIL ✗";

# Test 5: eval with builtin function call
my $eval_builtin = q{eval 'print 1+1;';};

print "Test 5: eval STRING with expression\n";
my $r5 = $parser->parse_string($eval_builtin);
printf "  Result: %s\n\n", $r5 ? "PASS ✓" : "FAIL ✗";
