#!/usr/bin/env perl
# ABOUTME: Test CLI options for app.pl including semiring selection
# ABOUTME: Verifies -c syntax check mode and --semiring option work correctly
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
use File::Temp qw(tempfile);
defer { done_testing() }

my $app_pl = "$RealBin/../../app.pl";

subtest '-c option for syntax checking with Boolean semiring' => sub {
    my ($fh, $filename) = tempfile();
    print $fh "class Foo { }\n";
    close $fh;

    my $output = `perl $app_pl -c -g Perl $filename 2>&1`;
    my $exit_code = $? >> 8;

    like $output, qr/syntax OK/i, '-c shows syntax OK for valid Perl';
    is $exit_code, 0, '-c exits with 0 for valid syntax';

    unlink $filename;
};

subtest '-c option rejects invalid syntax' => sub {
    my ($fh, $filename) = tempfile();
    print $fh "class { }\n";  # Invalid - missing class name
    close $fh;

    my $output = `perl $app_pl -c -g Perl $filename 2>&1`;
    my $exit_code = $? >> 8;

    like $output, qr/(syntax error|parse failed)/i, '-c shows error for invalid Perl';
    is $exit_code, 1, '-c exits with 1 for invalid syntax';

    unlink $filename;
};

subtest '--semiring Boolean option' => sub {
    my ($fh, $filename) = tempfile();
    print $fh "class Foo { }\n";
    close $fh;

    my $output = `perl $app_pl --semiring Boolean -g Perl $filename 2>&1`;
    my $exit_code = $? >> 8;

    ok $output, '--semiring Boolean produces output';
    is $exit_code, 0, '--semiring Boolean exits with 0 for valid syntax';

    unlink $filename;
};

subtest '--semiring SPPF option (default)' => sub {
    my ($fh, $filename) = tempfile();
    print $fh "class Foo { }\n";
    close $fh;

    my $output = `perl $app_pl --semiring SPPF -g Perl $filename 2>&1`;
    my $exit_code = $? >> 8;

    ok $output, '--semiring SPPF produces output';
    is $exit_code, 0, '--semiring SPPF exits with 0 for valid syntax';

    unlink $filename;
};

subtest '-c is equivalent to --semiring Boolean' => sub {
    my ($fh, $filename) = tempfile();
    print $fh "class Foo { }\n";
    close $fh;

    my $output_c = `perl $app_pl -c -g Perl $filename 2>&1`;
    my $exit_c = $? >> 8;

    my $output_bool = `perl $app_pl --semiring Boolean -g Perl $filename 2>&1`;
    my $exit_bool = $? >> 8;

    is $exit_c, $exit_bool, '-c and --semiring Boolean have same exit code';
    # Both should indicate success
    is $exit_c, 0, 'Both exit with 0 for valid syntax';

    unlink $filename;
};
