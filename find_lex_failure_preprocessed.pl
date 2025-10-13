#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Preprocessor::Heredoc;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my $file = 'perl-tests/base/lex.t';
my @lines = do { local (@ARGV) = $file; <> };

say "Testing lex.t with " . scalar(@lines) . " lines total (with heredoc preprocessing)";
say "Binary searching for parse failure point...\n";

# Binary search for the failing line
my $low = 1;
my $high = scalar @lines;

while ($low < $high) {
    my $mid = int(($low + $high) / 2);
    my $content = join('', @lines[0..$mid-1]);

    # Preprocess before parsing
    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $content);
    $preprocessor->transform();
    my $preprocessed = $preprocessor->output;

    if ($parser->parse_string($preprocessed)) {
        say "Lines 1-$mid: PASS";
        $low = $mid + 1;
    } else {
        say "Lines 1-$mid: FAIL";
        $high = $mid;
    }
}

say "\nParse fails at line $low";
say "Line $low: " . $lines[$low-1];
if ($low > 1) {
    say "\nContext (lines " . ($low-2) . "-" . ($low+2) . "):";
    for my $i (max(0, $low-3) .. min($#lines, $low+1)) {
        printf "%4d: %s", $i+1, $lines[$i];
    }
}

sub max { $_[0] > $_[1] ? $_[0] : $_[1] }
sub min { $_[0] < $_[1] ? $_[0] : $_[1] }
