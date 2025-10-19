#!/usr/bin/env perl
# ABOUTME: Test backslash-quoted heredoc support (<<\EOF syntax)
# ABOUTME: Verify preprocessor handles backslash-quoted heredoc delimiters
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 2;
use Chalk::BNF;
use FindBin qw($RealBin);
use Chalk::Parser;
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, '..', 'grammar', 'perl.bnf');
open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::BNF::build_chalk_grammar($bnf_content, 'Program');

my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    preprocess => ['Chalk::Preprocessor::Heredoc'],
);

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

# Test 1: Parse backslash heredoc in comma expression
my $input = q{eval <<\EOE, print $@;
print "test";
EOE
};

ok($parser->parse_string($input), 'backslash heredoc in comma expression');

# Test 2: Simple <<\EOF without eval
my $simple = q{print <<\EOF;
Hello
EOF
};

ok($parser->parse_string($simple), 'simple backslash heredoc');
