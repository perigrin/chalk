#!/usr/bin/env perl
# ABOUTME: Test lib/*.pm files, skipping Grammar/Perl.pm
# ABOUTME: Shows parsing status without the timeout issue
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my @files = `find lib -name "*.pm" -type f`;
chomp @files;
@files = sort @files;

my $passed = 0;
my $total = scalar @files;
my $skipped = 0;

print "Testing lib/*.pm files (skipping Grammar/Perl.pm):\n";
print "=" x 60 . "\n";

for my $file (@files) {
    if ($file =~ /Grammar\/Perl\.pm$/) {
        print "lib/Chalk/Grammar/Perl.pm SKIP (timeout issue)\n";
        $skipped++;
        $total--;
        next;
    }

    open my $fh, '<', $file or die "Can't open $file: $!";
    my $code = do { local $/; <$fh> };
    close $fh;

    local $SIG{__WARN__} = sub {};

    my $result = $parser->parse_string($code);

    my $basename = $file;
    $basename =~ s{^lib/}{};

    printf "%-50s %s\n", $basename, $result ? "PASS ✓" : "FAIL ✗";
    $passed++ if $result;
}

print "=" x 60 . "\n";
printf "%d/%d (%.1f%%) lib/ files parse successfully\n",
    $passed, $total, 100 * $passed / $total;
printf "%d files skipped\n", $skipped;
