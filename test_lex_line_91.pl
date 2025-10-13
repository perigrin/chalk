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

# Test lines 1-91 (should include complete heredoc)
say "=== Testing lines 1-91 ===";
my $test91 = join("\n", @lines[0..90]);
my $pp91 = Chalk::Preprocessor::HeredocV2->new(input => $test91);
$pp91->transform();
my $transformed91 = $pp91->output;

say "Last few lines of transformed 1-91:";
say join("\n", (split /\n/, $transformed91)[-8..-1]);

my $result91 = $parser->parse_string($transformed91);
say "\nLines 1-91: ", $result91 ? "✓ PASS" : "✗ FAIL";

# Show where line 91 is
say "\nLine 90 (index 89): '$lines[89]'";
say "Line 91 (index 90): '$lines[90]'";
say "Line 92 (index 91): '$lines[91]'";
