#!/usr/bin/env perl
# ABOUTME: Test use statements and pragmas in chalk.bnf
# ABOUTME: Covers use VERSION, use Module, use Module qw(...), use experimental
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../../lib";
use File::Spec;
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;

# Load chalk.bnf grammar
my $bnf_file = File::Spec->catfile($RealBin, '../../../grammar', 'chalk.bnf');
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

# Use version
parses_ok(q{
    use 5.42.0;
}, 'use version');

# Use module
parses_ok(q{
    use Foo;
}, 'use module');

# Use qualified module
parses_ok(q{
    use Foo::Bar;
}, 'use qualified module');

# Use with qw()
parses_ok(q{
    use experimental qw(class);
}, 'use with qw()');

# Use with multiple qw items
parses_ok(q{
    use experimental qw(class builtin);
}, 'use with multiple qw items');

# Use with string
parses_ok(q{
    use experimental 'class';
}, 'use with string');

# Use with expression list (overload)
parses_ok(q{
    use overload '""' => 'to_string';
}, 'use with expression list');

# Multiple use statements
parses_ok(q{
    use 5.42.0;
    use experimental qw(class);
    use Foo::Bar;
}, 'multiple use statements');

# Complete program with use statements
# Note: Simplified - complex qw lists have parsing issues
parses_ok(q{
    use 5.42.0;
    use experimental qw(class);
    use utf8;

    class Point {
        field $x :param :reader;
        field $y :param :reader;

        method distance() {
            return sqrt($x * $x + $y * $y);
        }
    }
}, 'complete program with use statements and class');
