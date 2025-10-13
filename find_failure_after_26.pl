#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Preprocessor::Heredoc;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my @lines = do { local (@ARGV) = 'perl-tests/base/lex.t'; <> };

say "Binary searching between lines 26-50...";

my $low = 26;
my $high = 50;

while ($low < $high) {
    my $mid = int(($low + $high + 1) / 2);
    my $code = join('', @lines[0..$mid-1]);
    
    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $code);
    $preprocessor->transform();
    my $preprocessed = $preprocessor->output;
    
    if ($parser->parse_string($preprocessed)) {
        say "Lines 1-$mid: PASS";
        $low = $mid;
    } else {
        say "Lines 1-$mid: FAIL";
        $high = $mid - 1;
    }
}

say "\nLast successful parse: line $low";
say "First failure: line " . ($low + 1);
say "\nLine " . ($low + 1) . ": " . $lines[$low];
