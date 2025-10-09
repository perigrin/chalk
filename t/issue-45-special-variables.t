#!/usr/bin/env perl
# ABOUTME: Tests for special variables support ($!, $^E, $/, etc.) - issue #45 phase 1
# ABOUTME: These are common Perl special variables used throughout legacy code

use 5.42.0;
use experimental qw(class);
use utf8;
use Test::More;
use lib 'lib';
use Chalk::Parser;
use Chalk::Grammar::Perl;
use Chalk::Semiring::Boolean;

# Create parser
my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test basic special variables
subtest 'basic special variables' => sub {
    # Error variables
    ok($parser->parse_string('$!'), 'Should parse: $!');
    ok($parser->parse_string('$^E'), 'Should parse: $^E');
    ok($parser->parse_string('$?'), 'Should parse: $?');
    ok($parser->parse_string('$@'), 'Should parse: $@');

    # Input/output variables
    ok($parser->parse_string('$/'), 'Should parse: $/');
    ok($parser->parse_string('$_'), 'Should parse: $_');
    ok($parser->parse_string('$|'), 'Should parse: $|');

    # Process variables
    ok($parser->parse_string('$$'), 'Should parse: $$');
    ok($parser->parse_string('$0'), 'Should parse: $0');
    ok($parser->parse_string('$^X'), 'Should parse: $^X');
};

# Test special variables in expressions
subtest 'special variables in expressions' => sub {
    ok($parser->parse_string('print $!'), 'Should parse: print $!');
    ok($parser->parse_string('my $err = $!'), 'Should parse: my $err = $!');
    ok($parser->parse_string('die "Error: $!"'), 'Should parse: die "Error: $!"');
    ok($parser->parse_string('$/ = "\n"'), 'Should parse: $/ = "\n"');
    ok($parser->parse_string('if ($@) { print $@ }'), 'Should parse: if ($@) { print $@ }');
};

# Test special variables in string interpolation
subtest 'special variables in string interpolation' => sub {
    ok($parser->parse_string('"Error: $!"'), 'Should parse: "Error: $!"');
    ok($parser->parse_string('"Error: $! ($^E)"'), 'Should parse: "Error: $! ($^E)"');
    ok($parser->parse_string('"Line: $_"'), 'Should parse: "Line: $_"');
};

# Test rs.t specific usage patterns
subtest 'rs.t specific patterns' => sub {
    # From rs.t line 13
    ok($parser->parse_string('die "error $! $^E opening"'),
       'Should parse: die "error $! $^E opening"');

    # From rs.t line 16
    ok($parser->parse_string('die "error $! $^E closing"'),
       'Should parse: die "error $! $^E closing"');

    # From rs.t line 37 - assignment to special variable
    ok($parser->parse_string('$/ = "\n"'),
       'Should parse: $/ = "\n"');

    # From rs.t line 65 - assignment to ref
    ok($parser->parse_string('$/ = \10'),
       'Should parse: $/ = \10');

    # From rs.t line 60 - special variables in print
    ok($parser->parse_string('print "# open failed $! $^E\n"'),
       'Should parse: print "# open failed $! $^E\n"');
};

done_testing();
