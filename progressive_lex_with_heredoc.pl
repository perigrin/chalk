#!/usr/bin/env perl
# ABOUTME: Progressive test with heredoc preprocessor to find next failure
# ABOUTME: Test in 10-line increments with preprocessing enabled
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::Heredoc'],
);

open my $fh, '<', 'perl-tests/base/lex.t' or die "Can't open lex.t: $!";
my @lines = <$fh>;
close $fh;

my $total_lines = scalar @lines;
print "Progressive lex.t parsing with heredoc preprocessor\n";
print "Total lines: $total_lines\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

# Test in 10-line increments
my $last_good = 0;
for (my $line_count = 10; $line_count <= $total_lines; $line_count += 10) {
    my $code = join('', @lines[0..$line_count-1]);

    my $result = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 10;
        my $r = $parser->parse_string($code);
        alarm 0;
        $r;
    };

    if ($@ && $@ =~ /timeout/) {
        printf "Lines 1-%4d: TIMEOUT\n", $line_count;
        last;
    } elsif ($result) {
        printf "Lines 1-%4d: PASS ✓ (%3d%%)\n", $line_count, int(100 * $line_count / $total_lines);
        $last_good = $line_count;
    } else {
        printf "Lines 1-%4d: FAIL ✗ (%3d%%)\n", $line_count, int(100 * $line_count / $total_lines);
        print "\nFailure region: lines " . ($last_good + 1) . "-$line_count\n";
        print "=" x 60 . "\n";

        # Show the problem lines
        my $start = $last_good;
        my $end = min($line_count, $start + 20);
        print "Lines $start-$end:\n";
        print "-" x 60 . "\n";
        for my $i ($start .. $end - 1) {
            printf "%4d: %s", $i + 1, $lines[$i];
        }
        last;
    }
}

if ($last_good == $total_lines) {
    print "\n✅ SUCCESS! Entire file parses with heredoc preprocessor!\n";
} elsif ($last_good > 0) {
    printf "\n⚠️  Parsing stopped at line %d (%.1f%% complete)\n",
           $last_good, 100 * $last_good / $total_lines;
}

sub min { $_[0] < $_[1] ? $_[0] : $_[1] }
