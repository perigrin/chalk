#!/usr/bin/env perl
# ABOUTME: Test parsing of $#array syntax (array length)
# ABOUTME: Verify $#array and $#$ref forms are supported
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 7;
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

my $parser = Chalk::Parser->new(grammar => $chalk_grammar);

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

# Basic array length
ok($parser->parse_string('$#array'), 'array length variable');
ok($parser->parse_string('$#output_lines'), 'array length with underscores');

# Array length of dereference
ok($parser->parse_string('$#$ref'), 'array length of dereferenced scalar');
ok($parser->parse_string('$#$existing_children'), 'array length dereference (SPPF.pm)');

# In expressions
ok($parser->parse_string('0..$#array'), 'range with array length');
ok($parser->parse_string('0..$#output_lines'), 'range with array length (actual usage)');

# With subscripts
ok($parser->parse_string('$array[$#array]'), 'last element access');
