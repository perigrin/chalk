#!/usr/bin/env perl
# ABOUTME: Test chalk parsing its own source code for true self-hosting
# ABOUTME: This is the ultimate test - can chalk parse itself?
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

# load the modular parser
use Chalk;

# Load the Perl grammar
require "$RealBin/../chalk-grammar.pl";
our $chalk_grammar;

local $| = 1;

# Read the actual chalk source as a string
open my $fh, '<:utf8', "$RealBin/../chalk" or die "Cannot read chalk: $!";
my $chalk_source = do { local $/; <$fh> };
close $fh;

my $length = length($chalk_source);
is $length, `perl -CSD -0777 -ne 'print length' chalk`,
  "Read $length characters from chalk source file";

# Check for expected content
diag("Validate chalk source file contents");
ok( $chalk_source =~ /class/,   "Found 'class' declarations" );
ok( $chalk_source =~ /Element/, "Found 'Element' class" );
ok( $chalk_source =~ /use/,     "Found 'use' declarations" );
ok( $chalk_source =~ /field/,   "Found 'field' declarations" );
ok( $chalk_source =~ /method/,  "Found 'method' declarations" );

# This is the ultimate test - try to parse the entire chalk file with lexemes:
diag "Parsing chalk source file ... this may take a while.";
my $parser = Chalk::Parser->new( grammar => $chalk_grammar );
my $result = $parser->parse_string($chalk_source);

# Debug: show how far we got
my $total_length = length($chalk_source);
diag "Self-hosting successful: $result\n";
ok $result, "Chalk successfully parses itself with lexemes!";

done_testing;
