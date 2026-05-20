# ABOUTME: Tests codegen consumes a hand-constructed MOP and produces valid output.
# ABOUTME: Per Phase 4, codegen reads only via MOP's public API - no parser-specific coupling.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(reftype);
use lib 'lib';

use Chalk::MOP;
use Chalk::Bootstrap::Perl::Target::Perl;

# Build a MOP without invoking the parser.
my $mop = Chalk::MOP->new;
my $cls = $mop->declare_class('Tiny');
$cls->declare_method('noop',
    params      => [],
    return_type => 'Void',
);
$cls->declare_field('$x',
    sigil      => '$',
    param_name => 'x',
    attributes => [':param'],
);

my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
my $result = $target->generate($mop);

ok(defined $result, 'generate($mop) returns a defined value');
is(reftype($result), 'HASH',
    'generate($mop) returns a hashref');

SKIP: {
    skip 'no hashref', 2 unless reftype($result // '') eq 'HASH';

    # Some entry should reference the Tiny class.
    my @vals = values $result->%*;
    ok(scalar(grep { /class\s+Tiny\b/ } @vals) >= 1,
        'output references the Tiny class')
        or diag('values: ' . join(' | ', map { substr($_, 0, 60) } @vals));

    ok(scalar(grep { /method\s+noop\b|sub\s+noop\b/ } @vals) >= 1,
        'output references the noop method')
        or diag('values: ' . join(' | ', map { substr($_, 0, 60) } @vals));
}

done_testing();
