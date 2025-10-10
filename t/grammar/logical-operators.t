#!/usr/bin/env perl
# ABOUTME: Tests for low-precedence logical operators (or/and) - issue #45 phase 2
# ABOUTME: These operators are distinct from || and && and commonly used for error handling

use 5.42.0;
use experimental qw(class);
use utf8;
use Test::More;
use lib 'lib';
use Chalk::Parser;
use Chalk::Grammar::Perl;
use Chalk::Semiring::Boolean;

# Create parser
my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test basic 'or' operator patterns
subtest 'or operator patterns' => sub {
    ok($parser->parse_string('$x or $y'),
       'Should parse: $x or $y');

    ok($parser->parse_string('1 or 0'),
       'Should parse: 1 or 0');

    ok($parser->parse_string('$result = func() or 0'),
       'Should parse: $result = func() or 0');

    ok($parser->parse_string('return 1 or die'),
       'Should parse: return 1 or die');
};

# Test basic 'and' operator patterns
subtest 'and operator patterns' => sub {
    ok($parser->parse_string('$x and $y'),
       'Should parse: $x and $y');

    ok($parser->parse_string('1 and 1'),
       'Should parse: 1 and 1');

    ok($parser->parse_string('$result = func() and 1'),
       'Should parse: $result = func() and 1');

    ok($parser->parse_string('$success and print "ok"'),
       'Should parse: $success and print "ok"');
};

# Test 'or die' pattern - extremely common in Perl
subtest 'or die patterns' => sub {
    ok($parser->parse_string('func() or die'),
       'Should parse: func() or die');

    ok($parser->parse_string('func() or die "error"'),
       'Should parse: func() or die "error"');

    ok($parser->parse_string('func() or die "Error: $!"'),
       'Should parse: func() or die "Error: $!"');

    ok($parser->parse_string('$x = func() or die "failed"'),
       'Should parse: $x = func() or die "failed"');
};

# Test 'or warn' pattern
subtest 'or warn patterns' => sub {
    ok($parser->parse_string('func() or warn'),
       'Should parse: func() or warn');

    ok($parser->parse_string('func() or warn "warning"'),
       'Should parse: func() or warn "warning"');

    ok($parser->parse_string('close $fh or warn "Close failed: $!"'),
       'Should parse: close $fh or warn "Close failed: $!"');
};

# Test 'and print' pattern
subtest 'and print patterns' => sub {
    ok($parser->parse_string('$success and print "ok"'),
       'Should parse: $success and print "ok"');

    ok($parser->parse_string('unlink "file" and print "Deleted\n"'),
       'Should parse: unlink "file" and print "Deleted\n"');
};

# Test patterns from rs.t - the exact failure case
subtest 'rs.t specific patterns' => sub {
    # From rs.t line 13 - this is the actual failure
    ok($parser->parse_string('open TESTFILE, ">./foo" or die "error $! $^E opening"'),
       'Should parse: open TESTFILE, ">./foo" or die "error $! $^E opening"');

    # From rs.t line 16
    ok($parser->parse_string('close TESTFILE or die "error $! $^E closing"'),
       'Should parse: close TESTFILE or die "error $! $^E closing"');

    # Simplified versions
    ok($parser->parse_string('open FH, ">file" or die'),
       'Should parse: open FH, ">file" or die');

    ok($parser->parse_string('close FH or warn'),
       'Should parse: close FH or warn');
};

# Test precedence - or/and are lower precedence than ||/&&
subtest 'precedence and chaining' => sub {
    # or/and bind looser than assignment
    ok($parser->parse_string('my $x = 1 or die'),
       'Should parse: my $x = 1 or die');

    # Multiple or operators
    ok($parser->parse_string('func1() or func2() or die'),
       'Should parse: func1() or func2() or die');

    # Multiple and operators
    ok($parser->parse_string('$a and $b and $c'),
       'Should parse: $a and $b and $c');

    # Mixed with high precedence operators
    ok($parser->parse_string('$x || $y or die'),
       'Should parse: $x || $y or die');
};

done_testing();
