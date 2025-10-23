#!/usr/bin/env perl
# ABOUTME: Tests for caret variables in braces (${^NAME}) - from perl-tests/base/lex.t line 129
# ABOUTME: These are special Perl variables like ${^ENCODING}, ${^UTF8CACHE}, etc.

use 5.42.0;
use experimental qw(class);
use utf8;
use Test::More;
use lib 'lib';
use Chalk::Parser;
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "..", "grammar", "perl.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");


# Create parser
my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test simple caret variables (baseline - should already work)
subtest 'simple caret variables' => sub {
    ok($parser->parse_string('$^X'), 'Should parse: $^X');
    ok($parser->parse_string('$^E'), 'Should parse: $^E');
    ok($parser->parse_string('$^O'), 'Should parse: $^O');
    ok($parser->parse_string('$^X = 1'), 'Should parse: $^X = 1');
};

# Test caret variables in braces - the main fix
subtest 'caret variables in braces' => sub {
    ok($parser->parse_string('${^XY}'), 'Should parse: ${^XY}');
    ok($parser->parse_string('${^ENCODING}'), 'Should parse: ${^ENCODING}');
    ok($parser->parse_string('${^UTF8CACHE}'), 'Should parse: ${^UTF8CACHE}');
    ok($parser->parse_string('${^XY} = 1'), 'Should parse: ${^XY} = 1');
    ok($parser->parse_string('${^TEST} = "splat"'), 'Should parse: ${^TEST} = "splat"');
};

# Test caret variables with space before brace
subtest 'caret variables with space before brace' => sub {
    ok($parser->parse_string('$ {^XY}'), 'Should parse: $ {^XY}');
    ok($parser->parse_string('$ {^XY} = 1'), 'Should parse: $ {^XY} = 1');
    ok($parser->parse_string('$ {^M}'), 'Should parse: $ {^M}');
};

# Test caret variables with spaces inside braces (from lex.t line 165)
subtest 'caret variables with spaces inside braces' => sub {
    ok($parser->parse_string('${ ^TEST }'), 'Should parse: ${ ^TEST }');
    ok($parser->parse_string('"${ ^TEST }"'), 'Should parse: "${ ^TEST }"');
};

# Test caret variables in expressions (from lex.t lines 129, 195-197)
subtest 'caret variables in expressions' => sub {
    ok($parser->parse_string('if (${^XY} != 23) { print "test" }'),
       'Should parse: if (${^XY} != 23) { print "test" }');
    ok($parser->parse_string('if ($ {^XY} != 23) { print "test" }'),
       'Should parse: if ($ {^XY} != 23) { print "test" }');
    ok($parser->parse_string('print "not " unless $ {^Quixote} eq "value"'),
       'Should parse: print "not " unless $ {^Quixote} eq "value"');
    ok($parser->parse_string('print "not " unless $ {^M} eq "value"'),
       'Should parse: print "not " unless $ {^M} eq "value"');
};

# Test array and hash caret variables (from lex.t lines 159-160)
subtest 'array and hash caret variables' => sub {
    ok($parser->parse_string('@{^TEST}'), 'Should parse: @{^TEST}');
    ok($parser->parse_string('%{^TEST}'), 'Should parse: %{^TEST}');
    ok($parser->parse_string('@{^TEST} = ("foo", "bar")'),
       'Should parse: @{^TEST} = ("foo", "bar")');
    ok($parser->parse_string('%{^TEST} = ("foo" => "FOO", "bar" => "BAR")'),
       'Should parse: %{^TEST} = ("foo" => "FOO", "bar" => "BAR")');
};

# Test caret variables in string interpolation (from lex.t lines 162, 165)
subtest 'caret variables in string interpolation' => sub {
    ok($parser->parse_string('"${^TEST}"'), 'Should parse: "${^TEST}"');
    ok($parser->parse_string('"${ ^TEST }"'), 'Should parse: "${ ^TEST }"');
    ok($parser->parse_string('print "not " if "${^TEST}" ne "splat"'),
       'Should parse: print "not " if "${^TEST}" ne "splat"');
};

# Test caret variables with subscripts (from lex.t lines 168, 171, 174)
subtest 'caret variables with subscripts' => sub {
    ok($parser->parse_string('${^TEST}[0]'), 'Should parse: ${^TEST}[0]');
    ok($parser->parse_string('${^TEST[0]}'), 'Should parse: ${^TEST[0]}');
    ok($parser->parse_string('${ ^TEST [1] }'), 'Should parse: ${ ^TEST [1] }');
    ok($parser->parse_string('${^TEST}{foo}'), 'Should parse: ${^TEST}{foo}');
    ok($parser->parse_string('${^TEST{foo}}'), 'Should parse: ${^TEST{foo}}');
    ok($parser->parse_string('${ ^TEST {bar} }'), 'Should parse: ${ ^TEST {bar} }');
};

done_testing();
