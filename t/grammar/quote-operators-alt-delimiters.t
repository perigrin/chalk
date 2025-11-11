#!/usr/bin/env perl
# ABOUTME: Test alternative quote operator delimiters
# ABOUTME: Verify qq(), qq[], q<>, q{} forms are supported
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 5;
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use Chalk::Parser;
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, '..', '..', 'grammar', 'chalk.bnf');
open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program');

my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    preprocess => ['Chalk::Preprocessor::Heredoc'],
);

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

# Test forms from lex.t lines 63-70
ok($parser->parse_string(q{print qq(ok 15\n);}), 'qq(text)');
ok($parser->parse_string(q{print qq[ok 16\n];}), 'qq[text]');
ok($parser->parse_string(q{print q<ok 17>;}), 'q<text>');
ok($parser->parse_string(q{print q{ok 18};}), 'q{text}');
ok($parser->parse_string(q{print qq{ok 19};}), 'qq{text}');
