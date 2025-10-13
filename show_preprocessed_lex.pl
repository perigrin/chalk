#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Preprocessor::Heredoc;

my $file = 'perl-tests/base/lex.t';
my $content = do { local (@ARGV, $/) = $file; <> };

# Preprocess heredocs
my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $content);
$preprocessor->transform();
my $preprocessed = $preprocessor->output;

my @lines = split /\n/, $preprocessed, -1;

say "Preprocessed lines 35-50:";
say "=" x 60;
for my $i (34..49) {
    printf "%3d: %s\n", $i+1, $lines[$i] // '';
}
