# ABOUTME: Documents that the distance vector set registry was removed (S1 deletion).
# ABOUTME: The set_reuse_stats accessor no longer exists; callers must not call it.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

# Helper to create terminal symbol
sub terminal($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => $value,
    );
}

# Helper to create reference symbol (nonterminal)
sub reference($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'reference',
        value => $value,
    );
}

my $grammar = [
    Chalk::Grammar::Rule->new(
        name        => 'Program',
        expressions => [
            [reference('Statement')],
            [reference('Program'), terminal(';'), reference('Statement')],
        ],
    ),
    Chalk::Grammar::Rule->new(
        name        => 'Statement',
        expressions => [[terminal('\\w+'), terminal('='), terminal('\\d+')]],
    ),
];

my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();

# S1 deletion: the set-reuse registry (Earley.pm lines 708-727) was removed
# because it built position key strings that no parsing logic ever consumed.
# The set_reuse_stats() accessor was removed with it. These tests confirm:
#   1. The parser still constructs and runs correctly without the registry.
#   2. The set_reuse_stats() method no longer exists on the parser.

# Test 1: parser constructs without error
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );
    ok(defined $parser, "parser constructs without set-registry fields");
}

# Test 2: parsing still works correctly after deletion
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );
    ok($parser->parse('x=1'), "single statement parses correctly");
    ok($parser->parse('x=1;y=2;z=3;a=4;b=5'), "repetitive input parses correctly");
}

# Test 3: set_reuse_stats accessor is gone — the method must not exist
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );
    ok(!$parser->can('set_reuse_stats'),
        "set_reuse_stats accessor removed along with registry");
}

# Test 4: other stats accessors still work
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );
    $parser->parse('x=1');
    ok($parser->can('scan_stats'),  "scan_stats accessor still present");
    ok($parser->can('gc_stats'),    "gc_stats accessor still present");
    my $scan = $parser->scan_stats();
    ok(defined $scan, "scan_stats returns defined value");
    ok(exists $scan->{total_matches}, "scan_stats has total_matches key");
}

done_testing;
