#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Preprocessor::HeredocV2;
use Chalk::Grammar::Perl;
use Chalk::Parser;

# Read the lex.t file
my $file = 'perl-tests/base/lex.t';
open my $fh, '<', $file or die "Cannot open $file: $!";
my $content = do { local $/; <$fh> };
close $fh;

my @lines = split /\n/, $content;
say "Total lines in lex.t: ", scalar(@lines);

# Preprocess
my $preprocessor = Chalk::Preprocessor::HeredocV2->new(input => $content);
$preprocessor->transform();
my $transformed = $preprocessor->output;

# Binary search for how much we can parse
my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my $left = 1;
my $right = scalar(@lines);
my $max_parseable = 0;

while ($left <= $right) {
    my $mid = int(($left + $right) / 2);
    my $test_content = join("\n", @lines[0..$mid-1]);

    # Preprocess this subset
    my $pp = Chalk::Preprocessor::HeredocV2->new(input => $test_content);
    $pp->transform();
    my $test_transformed = $pp->output;

    if ($parser->parse_string($test_transformed)) {
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
