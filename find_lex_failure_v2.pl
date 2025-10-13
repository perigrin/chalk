#!/usr/bin/env perl
# ABOUTME: Binary search to find exact failure point in lex.t with HeredocV2
# ABOUTME: More efficient than 10-line increments for finding precise failure
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::HeredocV2'],
);

open my $fh, '<', 'perl-tests/base/lex.t' or die;
my @lines = <$fh>;
close $fh;

my $total_lines = scalar @lines;
print "Binary search for lex.t failure with HeredocV2\n";
print "Total lines: $total_lines\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

my $low = 1;
my $high = $total_lines;
my $last_good = 0;

while ($low <= $high) {
    my $mid = int(($low + $high) / 2);
    my $code = join('', @lines[0..$mid-1]);

    my $result = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 15;
        my $r = $parser->parse_string($code);
        alarm 0;
        $r;
    };

    if ($@ && $@ =~ /timeout/) {
        printf "Lines 1-%4d: TIMEOUT\n", $mid;
        $high = $mid - 1;
    } elsif ($result) {
        printf "Lines 1-%4d: PASS (%3d%%)\n", $mid, int(100 * $mid / $total_lines);
        $last_good = $mid;
        $low = $mid + 1;
    } else {
        printf "Lines 1-%4d: FAIL (%3d%%)\n", $mid, int(100 * $mid / $total_lines);
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

if ($last_good == $total_lines) {
    print "\n✅ FULL FILE PARSES!\n";
}

sub min { $_[0] < $_[1] ? $_[0] : $_[1] }
