#!/usr/bin/env perl
# ABOUTME: Debug script to test exact lines 1-8 of Boolean.pm
# ABOUTME: Identifies parse failure point

use 5.42.0;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::ChalkSyntax;

open my $fh, '<:utf8', "$RealBin/grammar/chalk.bnf" or die $!;
my $bnf = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');
my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);

# Exact lines 1-8
my $code = <<'CODE';
# ABOUTME: Boolean semiring for fast parse validation without position tracking
# ABOUTME: Provides simple true/false parsing for syntax checking similar to perl -c
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::BooleanElement :isa(Chalk::Element) {
CODE

print "Lines 1-8: ";
my $result = $parser->parse_string($code);
print $result ? "SUCCESS" : "FAIL", "\n";
