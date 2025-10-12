#!/usr/bin/env perl
# ABOUTME: Test s/// substitution operator parsing
# ABOUTME: Verify various delimiter forms work correctly
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 5;
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

ok($parser->parse_string('s|::|/|g'), 'pipe delimiter');
ok($parser->parse_string('s/::/\//g'), 'slash delimiter');
ok($parser->parse_string('s!pattern!replacement!gi'), 'bang delimiter');
ok($parser->parse_string('s#foo#bar#'), 'hash delimiter');
ok($parser->parse_string('(my $x = "Foo::Bar") =~ s|::|/|g'), 'full expression with binding');
