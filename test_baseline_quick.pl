#!/usr/bin/env perl
# ABOUTME: Quick test of previously failing baseline files
# ABOUTME: Shows which files now parse after grammar improvements
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my @files = (
    'lib/Chalk/Grammar/Perl.pm',
    'lib/Chalk/Parser.pm',
    'lib/Chalk/Preprocessor/Heredoc.pm',
    'lib/Chalk/Semiring/Composite.pm',
    'lib/Chalk/Semiring/SPPF.pm',
);

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

for my $file (@files) {
    open my $fh, '<', $file or die "Can't open $file: $!";
    my $code = do { local $/; <$fh> };
    close $fh;

    # Suppress parsing warnings for this quick test
    local $SIG{__WARN__} = sub {};

    my $result = $parser->parse_string($code);
    printf "%-40s %s\n", $file, $result ? "PASS ✓" : "FAIL ✗";
}
