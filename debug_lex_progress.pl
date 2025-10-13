#!/usr/bin/env perl
# ABOUTME: Debug where lex.t parsing stops after bare regex fix
# ABOUTME: Binary search to find the exact failing line
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my $file = 'perl-tests/base/lex.t';
open my $fh, '<', $file or die "Can't open $file: $!";
my @lines = <$fh>;
close $fh;

my $total_lines = scalar @lines;
print "Debugging lex.t parsing progress\n";
print "Total lines: $total_lines\n";
print "=" x 60 . "\n";

# Binary search to find where it fails
my $low = 1;
my $high = $total_lines;
my $last_good = 0;

while ($low <= $high) {
    my $mid = int(($low + $high) / 2);
    my $code = join('', @lines[0..$mid-1]);

    local $SIG{__WARN__} = sub {};
    my $result = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 10;
        my $r = $parser->parse_string($code);
        alarm 0;
        $r;
    };

    if ($@ && $@ =~ /timeout/) {
        print "Lines 1-$mid: TIMEOUT\n";
        $high = $mid - 1;
    } elsif ($result) {
        print "Lines 1-$mid: PASS (", int(100 * $mid / $total_lines), "%)\n";
        $last_good = $mid;
        $low = $mid + 1;
    } else {
        print "Lines 1-$mid: FAIL (", int(100 * $mid / $total_lines), "%)\n";
        $high = $mid - 1;
    }
}

print "=" x 60 . "\n";
printf "Last successful parse: lines 1-%d (%.1f%%)\n", $last_good, 100 * $last_good / $total_lines;

if ($last_good < $total_lines) {
    print "\nProblem area (lines " . ($last_good + 1) . "-" . ($last_good + 10) . "):\n";
    print "-" x 60 . "\n";
    for my $i ($last_good .. min($last_good + 9, $total_lines - 1)) {
        printf "%4d: %s", $i + 1, $lines[$i];
    }
}

sub min { $_[0] < $_[1] ? $_[0] : $_[1] }
