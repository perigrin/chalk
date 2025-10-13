#!/usr/bin/env perl
# ABOUTME: Debug Grammar/Perl.pm by parsing progressively larger chunks
# ABOUTME: Find the exact line where parsing stops or slows down
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my $file = 'lib/Chalk/Grammar/Perl.pm';
open my $fh, '<', $file or die "Can't open $file: $!";
my @lines = <$fh>;
close $fh;

my $total_lines = scalar @lines;
print "Testing $total_lines lines from $file\n";
print "=" x 60 . "\n";

# Binary search to find where it fails
my $low = 1;
my $high = $total_lines;
my $last_good = 0;

while ($low <= $high) {
    my $mid = int(($low + $high) / 2);
    my $code = join('', @lines[0..$mid-1]);

    print "Testing lines 1-$mid... ";

    # Try with 10 second timeout
    my $result = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 10;
        my $r = $parser->parse_string($code);
        alarm 0;
        $r;
    };

    if ($@ && $@ =~ /timeout/) {
        print "TIMEOUT\n";
        $high = $mid - 1;
    } elsif ($result) {
        print "PASS\n";
        $last_good = $mid;
        $low = $mid + 1;
    } else {
        print "FAIL\n";
        $high = $mid - 1;
    }
}

print "=" x 60 . "\n";
print "Last successful parse: lines 1-$last_good\n";
if ($last_good < $total_lines) {
    print "Problem area: lines " . ($last_good + 1) . "-" . ($last_good + 10) . "\n";
    print "\n";
    for my $i ($last_good .. min($last_good + 9, $total_lines - 1)) {
        printf "%4d: %s", $i + 1, $lines[$i];
    }
}

sub min { $_[0] < $_[1] ? $_[0] : $_[1] }
