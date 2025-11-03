#!/usr/bin/env perl
# ABOUTME: Test that app.pl generates IR by default (without --generate-ir flag)
# ABOUTME: Verifies issue #112 - IR generation should be standard behavior
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use lib 'lib';
use Test::More;
use File::Temp qw(tempfile);

# Test that app.pl generates IR by default (not just syntax check)
{
    # Create a simple test program
    my $test_program = q{use 5.42.0;
my $x = 42;
};

    # Write test program to a temp file
    my ($fh, $filename) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $test_program;
    close $fh;

    # Run app.pl without any flags (default behavior)
    my $output = `$^X app.pl $filename 2>&1`;
    my $exit_code = $? >> 8;

    # The parse should succeed
    is($exit_code, 0, 'app.pl exits successfully with simple program');
    like($output, qr/Parse successful/, 'app.pl reports parse success');

    # Verify IR generation (issue #112)
    like($output, qr/Generated IR with \d+ nodes/, 'app.pl reports IR generation by default');
    like($output, qr/Composite/, 'app.pl uses Composite semiring by default');
}

# Test that -c flag still does syntax-only checking (no IR generation)
{
    # Create a simple test program
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
    like($output, qr/syntax OK/, 'app.pl -c reports syntax OK');
}

done_testing();
