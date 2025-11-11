#!/usr/bin/env perl
# ABOUTME: Validates that all test files have ABOUTME comments explaining their purpose
# ABOUTME: This meta-test ensures test suite documentation standards are maintained

use v5.42;
use Test::More;
use File::Find;

my @test_files;
find(
    sub {
        return unless /\.t$/;
        return if $File::Find::dir =~ m{/validation$} && $_ eq 'test-aboutme-comments.t';
        push @test_files, $File::Find::name;
    },
    't/'
);

plan tests => scalar(@test_files);

for my $test_file (sort @test_files) {
    open my $fh, '<:encoding(UTF-8)', $test_file
        or die "Cannot open $test_file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    my $has_aboutme = $content =~ /^# ABOUTME:/m;

    ok($has_aboutme, "$test_file has ABOUTME comment")
        or diag("Test file $test_file is missing ABOUTME comment explaining its purpose");
}

done_testing();
