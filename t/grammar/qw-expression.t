#!/usr/bin/env perl
# ABOUTME: Tests that qw() works as an expression (not just in use statements)
# ABOUTME: Covers qw() as function argument, variable assignment, and direct function call
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../lib";
use File::Spec;
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;

# Load chalk.bnf grammar
my $bnf_file = File::Spec->catfile($RealBin, '../../grammar', 'chalk.bnf');
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program');
my $semiring = Chalk::Semiring::Boolean->new();

sub parses_ok {
    my ($code, $name) = @_;
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );
    my $result = $parser->parse_string($code);
    ok($result, $name) or diag("Failed to parse: $code");
}

# Test: qw() with qualified identifiers (the ACTUAL issue from #345)
parses_ok(q{
    return any { $other isa $_ } qw(Chalk::Grammar::Chalk::Type::Object Chalk::Grammar::Chalk::Type::Ref);
}, 'qw() works with qualified identifiers as function argument');

# Test: qw() as function argument with any (simpler barewords)
parses_ok(q{
    return any { $other isa $_ } qw(Foo Bar);
}, 'qw() works as function argument to any');

# Test: qw() in variable assignment
parses_ok(q{
    my @list = qw(foo bar baz);
}, 'qw() works in variable assignment');

# Test: qw() as direct function argument
parses_ok(q{
    process_list(qw(item1 item2 item3));
}, 'qw() works as direct function argument');

# Test: qw() in return statement
parses_ok(q{
    return qw(one two three);
}, 'qw() works in return statement');

# Test: qw() with grep (list operator)
parses_ok(q{
    my @filtered = grep { $_ ne 'b' } qw(a b c);
}, 'qw() works with grep');

# Test: qw() with map (list operator)
parses_ok(q{
    my @upper = map { uc $_ } qw(a b c);
}, 'qw() works with map');

# Test: qw() with colon-prefixed symbols
parses_ok(q{
    my @symbols = qw(:foo :bar :baz);
}, 'qw() works with colon-prefixed symbols');
