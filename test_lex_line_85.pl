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

# Test lines 1-84 (should pass)
say "=== Testing lines 1-84 ===";
my $test84 = join("\n", @lines[0..83]);
my $pp84 = Chalk::Preprocessor::HeredocV2->new(input => $test84);
$pp84->transform();
my $transformed84 = $pp84->output;

say "Last few lines of transformed 1-84:";
say join("\n", (split /\n/, $transformed84)[-5..-1]);

my $result84 = $parser->parse_string($transformed84);
say "\nLines 1-84: ", $result84 ? "✓ PASS" : "✗ FAIL";

# Test lines 1-85 (currently fails)
say "\n=== Testing lines 1-85 ===";
my $test85 = join("\n", @lines[0..84]);
my $pp85 = Chalk::Preprocessor::HeredocV2->new(input => $test85);
$pp85->transform();
my $transformed85 = $pp85->output;

say "Last few lines of transformed 1-85:";
say join("\n", (split /\n/, $transformed85)[-5..-1]);

my $result85 = $parser->parse_string($transformed85);
say "\nLines 1-85: ", $result85 ? "✓ PASS" : "✗ FAIL";

# Show what line 85 actually is
say "\n=== Line 85 content ===";
say "Line 85: '$lines[84]'";
say "Line 86: '$lines[85]'";
say "Line 87: '$lines[86]'";
