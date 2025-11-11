#!/usr/bin/env perl
# ABOUTME: Test that app.pl generates IR and executes by default (not just syntax check)
# ABOUTME: Verifies issue #112 - IR generation and execution should be standard behavior
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use lib 'lib';
use Test::More;
use File::Temp qw(tempfile);

# Test that app.pl generates IR and executes by default (not just syntax check)
{
    # Create a test program that returns a value
    my $test_program = q{use 5.42.0;
my $x = 42;
return $x;
};

    # Write test program to a temp file
    my ($fh, $filename) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $test_program;
    close $fh;

    # Run app.pl without any flags (default behavior)
    my $output = `$^X app.pl $filename 2>&1`;
    my $exit_code = $? >> 8;

    # The execution should succeed
    is($exit_code, 0, 'app.pl exits successfully with simple program');

    # Verify IR generation and execution (issue #112)
    # app.pl now executes programs via CEK interpreter and prints the result
    like($output, qr/^42\s*$/s, 'app.pl generates IR, executes, and prints result (not just syntax check)');
}

# Test with a more complex computation
{
    my $test_program = q{use 5.42.0;
my $a = 10;
my $b = 5;
my $result = $a + $b;
return $result;
};

    my ($fh, $filename) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $test_program;
    close $fh;

    my $output = `$^X app.pl $filename 2>&1`;
    my $exit_code = $? >> 8;

    is($exit_code, 0, 'app.pl exits successfully with arithmetic');
    like($output, qr/^15\s*$/s, 'app.pl correctly executes arithmetic and returns result');
}

# Test that -c flag still does syntax-only checking (no execution)
{
    # Create a test program
    my $test_program = q{use 5.42.0;
my $y = 100;
};

    # Write test program to a temp file
    my ($fh, $filename) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $test_program;
    close $fh;

    # Run app.pl with -c flag (syntax check mode)
    my $output = `$^X app.pl -c $filename 2>&1`;
    my $exit_code = $? >> 8;

    # The syntax check should succeed
    is($exit_code, 0, 'app.pl -c exits successfully');
    like($output, qr/syntax OK/, 'app.pl -c reports syntax OK (no execution)');
}

# Test that -c flag doesn't execute code with side effects
{
    # Program that would print if executed, but -c should only check syntax
    my $test_program = q{use 5.42.0;
my $x = 42;
return $x;
};

    my ($fh, $filename) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $test_program;
    close $fh;

    my $output = `$^X app.pl -c $filename 2>&1`;
    my $exit_code = $? >> 8;

    is($exit_code, 0, 'app.pl -c exits successfully with return statement');
    like($output, qr/syntax OK/, 'app.pl -c only checks syntax');
    unlike($output, qr/42/, 'app.pl -c does not execute and print return value');
}

done_testing();
