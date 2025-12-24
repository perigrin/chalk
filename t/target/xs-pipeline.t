#!/usr/bin/env perl
# ABOUTME: Tests that --target=xs flag wires XS target into compilation pipeline
# ABOUTME: Verifies CLI flag parsing and basic XS target invocation
use 5.42.0;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../../tools";

# Use plenv to ensure correct Perl version
my $perl = "$ENV{HOME}/.plenv/versions/5.42.0/bin/perl";

# Test 1: Verify --target=xs flag is recognized without error
{
    my $test_prog = 'sub add($x, $y) { return $x + $y; }';
    open my $fh, '>', '/tmp/xs_pipeline_test.pl' or die "Cannot create temp file: $!";
    print $fh $test_prog;
    close $fh;

    my $output = `$perl $FindBin::Bin/../../app.pl --target=xs --module=TestModule /tmp/xs_pipeline_test.pl 2>&1`;
    my $exit_code = $? >> 8;

    # The command should not fail with "Unknown option" error
    unlike($output, qr/Unknown option/,
        '--target=xs flag should be recognized');

    # Clean up
    unlink '/tmp/xs_pipeline_test.pl';
}

# Test 2: Verify --module flag is recognized
{
    my $test_prog = 'sub add($x, $y) { return $x + $y; }';
    open my $fh, '>', '/tmp/xs_pipeline_test2.pl' or die "Cannot create temp file: $!";
    print $fh $test_prog;
    close $fh;

    my $output = `$perl $FindBin::Bin/../../app.pl --target=xs --module=MyModule /tmp/xs_pipeline_test2.pl 2>&1`;

    # The command should not fail with "Unknown option" error
    unlike($output, qr/Unknown option/,
        '--module flag should be recognized');

    # Clean up
    unlink '/tmp/xs_pipeline_test2.pl';
}

# Test 3: Verify XS target is invoked (basic smoke test)
# Since schedule_emission() returns empty array, we expect no output but no crash
{
    my $test_prog = 'sub add($x, $y) { return $x + $y; }';
    open my $fh, '>', '/tmp/xs_pipeline_test3.pl' or die "Cannot create temp file: $!";
    print $fh $test_prog;
    close $fh;

    my $output = `$perl $FindBin::Bin/../../app.pl --target=xs --module=TestMod /tmp/xs_pipeline_test3.pl 2>&1`;
    my $exit_code = $? >> 8;

    # Should not crash - exit code should be 0
    is($exit_code, 0,
        'XS pipeline should not crash even with empty schedule_emission');

    # Clean up
    unlink '/tmp/xs_pipeline_test3.pl';
}

done_testing();
