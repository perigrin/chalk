#!/usr/bin/env perl
# ABOUTME: Test parsing of $#array syntax (array length)
# ABOUTME: Verify $#array and $#$ref forms are supported
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 7;
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

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
