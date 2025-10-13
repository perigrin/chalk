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

# Spot check specific lines
my @check_lines = (84, 90, 92, 95, 100, 110, 120);

for my $line (@check_lines) {
    my $result = test_lines($line);
    my $status = $result ? "✓ PASS" : "✗ FAIL";
    printf "Lines 1-%-3d: %s", $line, $status;
    if (!$result && $line <= scalar(@lines)) {
        print " (line $line: '$lines[$line-1]')";
    }
    print "\n";
}
