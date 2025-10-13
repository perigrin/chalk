#!/usr/bin/env perl
# ABOUTME: Debug what's failing in lex.t
# ABOUTME: Shows where parsing stops in the lex.t file
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my $file = 'perl-tests/base/lex.t';
open my $fh, '<', $file or die "Can't open $file: $!";
my $code = do { local $/; <$fh> };
close $fh;

# Enable warnings to see where it stops
my $result = $parser->parse_string($code);

if (!$result) {
    print "FAILED\n";
}
