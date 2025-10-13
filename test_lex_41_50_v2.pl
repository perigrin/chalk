#!/usr/bin/env perl
# ABOUTME: Test lex.t lines 41-50 with HeredocV2
# ABOUTME: Debug why progressive test fails but isolated nested test passes
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::HeredocV2'],
);

print "Testing lex.t lines 41-50 with HeredocV2\n";
print "=" x 60 . "\n\n";

local $SIG{__WARN__} = sub {};

# Read actual lines from lex.t
open my $fh, '<', 'perl-tests/base/lex.t' or die;
my @lines = <$fh>;
close $fh;

# Test lines 41-50
my $code = join('', @lines[40..49]);  # 0-indexed

print "Code to parse:\n";
print "-" x 60 . "\n";
for my $i (40..49) {
    printf "%4d: %s", $i+1, $lines[$i];
}
print "\n";

print "Parsing...\n";
my $result = $parser->parse_string($code);
printf "Result: %s\n\n", $result ? "PASS ✓" : "FAIL ✗";

if (!$result) {
    # Try with more context - lines 1-50
    print "Trying with full context (lines 1-50)...\n";
    my $full = join('', @lines[0..49]);
    my $r2 = $parser->parse_string($full);
    printf "Result: %s\n\n", $r2 ? "PASS ✓" : "FAIL ✗";
}
