#!/usr/bin/env perl
# ABOUTME: Test parsing progress on t/*.t files
# ABOUTME: Shows comprehensive parsing status of test suite
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Use find to get all files
my @files = `find t -name "*.t" -type f`;
chomp @files;
@files = sort @files;

my $passed = 0;
my $total = scalar @files;

print "Testing t/*.t files:\n";
print "=" x 60 . "\n";

for my $file (@files) {
    open my $fh, '<', $file or die "Can't open $file: $!";
    my $code = do { local $/; <$fh> };
    close $fh;

    # Suppress parsing warnings
    local $SIG{__WARN__} = sub {};

    my $result = $parser->parse_string($code);

    my $basename = $file;
    $basename =~ s{^t/}{};

    printf "%-50s %s\n", $basename, $result ? "PASS ✓" : "FAIL ✗";
    $passed++ if $result;
}

print "=" x 60 . "\n";
printf "%d/%d (%.1f%%) t/ files parse successfully\n",
    $passed, $total, 100 * $passed / $total;
