#!/usr/bin/env perl
# ABOUTME: Test full Parser.pm file parsing
# ABOUTME: Check if Parser.pm now parses completely
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my $file = 'lib/Chalk/Parser.pm';
open my $fh, '<', $file or die "Can't open $file: $!";
my $code = do { local $/; <$fh> };
close $fh;

# Suppress parsing warnings
local $SIG{__WARN__} = sub {};

my $result = $parser->parse_string($code);
printf "%-40s %s\n", $file, $result ? "PASS ✓" : "FAIL ✗";
