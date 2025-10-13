#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my $file = 'perl-tests/base/lex.t';
my @lines = do { local (@ARGV) = $file; <> };

# Binary search for the failing line
my $low = 1;
my $high = scalar @lines;

say "Testing lex.t with " . scalar(@lines) . " lines total";
say "Binary searching for parse failure point...\n";

while ($low < $high) {
    my $mid = int(($low + $high) / 2);
    my $content = join('', @lines[0..$mid-1]);

    if ($parser->parse_string($content)) {
        say "Lines 1-$mid: ✓ PASS";
        $low = $mid + 1;
    } else {
        say "Lines 1-$mid: ✗ FAIL";
        $high = $mid;
    }
}

say "\nParse fails at line $low";
say "Line $low: " . $lines[$low-1];
