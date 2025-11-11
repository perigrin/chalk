#!/usr/bin/env perl
# ABOUTME: Test s/// substitution operator parsing
# ABOUTME: Verify various delimiter forms work correctly
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 5;
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use Chalk::Parser;
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "..", "grammar", "chalk.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");

my $parser = Chalk::Parser->new(grammar => $chalk_grammar);

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

ok($parser->parse_string('s|::|/|g'), 'pipe delimiter');
ok($parser->parse_string('s/::/\//g'), 'slash delimiter');
ok($parser->parse_string('s!pattern!replacement!gi'), 'bang delimiter');
ok($parser->parse_string('s#foo#bar#'), 'hash delimiter');
ok($parser->parse_string('(my $x = "Foo::Bar") =~ s|::|/|g'), 'full expression with binding');
