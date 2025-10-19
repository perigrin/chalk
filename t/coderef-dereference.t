#!/usr/bin/env perl
# ABOUTME: Test parsing of coderef dereferencing syntax ($sub->($args))
# ABOUTME: Verify that arrow operator with parentheses calls code references
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 6;
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

# Basic coderef call
ok($parser->parse_string('$sub->()'), 'coderef call with no args');
ok($parser->parse_string('$sub->(42)'), 'coderef call with one arg');
ok($parser->parse_string('$sub->(1, 2, 3)'), 'coderef call with multiple args');

# Coderef in statement context
ok($parser->parse_string('$is_excluded->($pos)'), 'coderef call in conditional (from Heredoc.pm)');
ok($parser->parse_string('next if $is_excluded->($pos)'), 'coderef call with statement modifier');

# Complex coderef expressions
ok($parser->parse_string('my $result = $callback->($data)'), 'coderef call in assignment');
