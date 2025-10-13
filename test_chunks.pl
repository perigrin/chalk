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

# Test various chunks
for my $n (26, 50, 100, 200, 400, 709) {
    my $code = join('', @lines[0..min($n-1, $#lines)]);
    
    # Preprocess
    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $code);
    $preprocessor->transform();
    my $preprocessed = $preprocessor->output;
    
    my $result = $parser->parse_string($preprocessed);
    printf "Lines 1-%d: %s\n", min($n, scalar(@lines)), ($result ? "PASS" : "FAIL");
}

sub min { $_[0] < $_[1] ? $_[0] : $_[1] }
