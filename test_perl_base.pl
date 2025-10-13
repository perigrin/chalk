#!/usr/bin/env perl
# ABOUTME: Test parsing of perl-tests/base/*.t files
# ABOUTME: Shows progress on parsing Perl's core base test suite
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my @files = glob('perl-tests/base/*.t');
@files = sort @files;

my $passed = 0;
my $total = scalar @files;

for my $file (@files) {
    open my $fh, '<', $file or die "Can't open $file: $!";
    my $code = do { local $/; <$fh> };
    close $fh;

    # Suppress parsing warnings
    local $SIG{__WARN__} = sub {};

    my $result = $parser->parse_string($code);

    my $basename = $file;
    $basename =~ s{^perl-tests/base/}{};

    printf "%-30s %s\n", $basename, $result ? "PASS ✓" : "FAIL ✗";
    $passed++ if $result;
}

printf "\n%d/%d (%.1f%%) base tests parse successfully\n",
    $passed, $total, 100 * $passed / $total;
