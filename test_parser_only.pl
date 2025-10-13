#!/usr/bin/env perl
# ABOUTME: Test only Parser.pm parsing with s/// support
# ABOUTME: Focus on the specific failing line
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Test just the problematic line
my $code = '(my $file = $preprocessor_class) =~ s|::|/|g;';

my $result = $parser->parse_string($code);
printf "%-50s %s\n", $code, $result ? "PASS ✓" : "FAIL ✗";
