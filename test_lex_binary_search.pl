#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Preprocessor::HeredocV2;
use Chalk::Grammar::Perl;
use Chalk::Parser;

# Read lex.t
my $file = 'perl-tests/base/lex.t';
open my $fh, '<', $file or die "Cannot open $file: $!";
my $content = do { local $/; <$fh> };
close $fh;

my @lines = split /\n/, $content;
say "Total lines in lex.t: ", scalar(@lines);

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

sub test_lines {
    my ($end_line) = @_;
    my $test_content = join("\n", @lines[0..$end_line-1]);
    my $pp = Chalk::Preprocessor::HeredocV2->new(input => $test_content);
    $pp->transform();
    my $transformed = $pp->output;
    return $parser->parse_string($transformed);
}

# Binary search for maximum parseable line
my $left = 1;
my $right = scalar(@lines);
my $max_parseable = 0;

while ($left <= $right) {
    my $mid = int(($left + $right) / 2);

    if (test_lines($mid)) {
        $max_parseable = $mid;
        $left = $mid + 1;
    } else {
        $right = $mid - 1;
    }
}

my $pct = sprintf("%.1f", ($max_parseable / scalar(@lines)) * 100);
say "Max parseable line: $max_parseable / ", scalar(@lines), " ($pct%)";

if ($max_parseable < scalar(@lines)) {
    say "\nFailed at line ", $max_parseable + 1, ":";
    say $lines[$max_parseable];
}
