#!/usr/bin/env perl
use 5.42.0;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Preprocessor::Heredoc;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my $file = 'perl-tests/base/lex.t';
my @lines = do { local (@ARGV) = $file; <> };

# Test lines 1-26 without preprocessing
say "Lines 1-26 WITHOUT preprocessing:";
my $code_raw = join('', @lines[0..25]);
my $result_raw = $parser->parse_string($code_raw);
say $result_raw ? "SUCCESS" : "FAILED";
say "-" x 60;

# Test lines 1-26 with preprocessing
say "Lines 1-26 WITH preprocessing:";
my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $code_raw);
$preprocessor->transform();
my $code_preprocessed = $preprocessor->output;
my $result_preprocessed = $parser->parse_string($code_preprocessed);
say $result_preprocessed ? "SUCCESS" : "FAILED";
say "-" x 60;

# Show what the preprocessed version looks like
say "Preprocessed code:";
say $code_preprocessed;
