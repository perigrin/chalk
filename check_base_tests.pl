#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Preprocessor::Heredoc;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my @test_files = glob("perl-tests/base/*.t");

for my $file (sort @test_files) {
    my $content = do { local (@ARGV, $/) = $file; <> };

    # Preprocess heredocs
    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $content);
    $preprocessor->transform();
    my $preprocessed = $preprocessor->output;

    my $result = $parser->parse_string($preprocessed);
    my $status = $result ? "✓ PASS" : "✗ FAIL";
    printf "%-30s %s\n", $file, $status;
}
