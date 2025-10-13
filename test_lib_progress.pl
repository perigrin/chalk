#!/usr/bin/env perl
# ABOUTME: Test parsing progress on lib/*.pm files
# ABOUTME: Shows how many library files parse successfully
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my @files = glob('lib/**/*.pm');
@files = sort @files;

my $passed = 0;
my $total = scalar @files;

print "Testing lib/*.pm files:\n";
print "=" x 60 . "\n";

for my $file (@files) {
    open my $fh, '<', $file or die "Can't open $file: $!";
    my $code = do { local $/; <$fh> };
    close $fh;

    # Suppress parsing warnings
    local $SIG{__WARN__} = sub {};

    my $result = $parser->parse_string($code);

    my $basename = $file;
    $basename =~ s{^lib/}{};

    printf "%-50s %s\n", $basename, $result ? "PASS ✓" : "FAIL ✗";
    $passed++ if $result;
}

printf "\n%d/%d (%.1f%%) lib/ files parse successfully\n",
    $passed, $total, 100 * $passed / $total;
