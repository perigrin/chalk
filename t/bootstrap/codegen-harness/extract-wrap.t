# ABOUTME: Tests the extract+wrap step: turns a === TAG corpus snippet into a runnable program.
# ABOUTME: Verifies the wrapped program runs under perl 5.42 and yields a non-empty record.
use 5.42.0;
use utf8;

use Test2::V0;
use lib 'lib';

use Chalk::CodeGen::Harness::RunUnderPerl;

use constant Oracle => 'Chalk::CodeGen::Harness::RunUnderPerl';

# Test 1: extract_snippet pulls out the body for a named tag from a corpus string
my $CORPUS = <<'END_CORPUS';
=== A1: bare VarDecl
class C { method m() { my $x = 1; return $x; } }
=== A5: VarDecl field
class C { field $x :param; method m() { return $x; } }
=== B2: bare print
class C { method m() { print "hi"; return 1; } }
END_CORPUS

my $extracted_a1 = Oracle->extract_snippet($CORPUS, 'A1');
like( $extracted_a1, qr/class C/, 'extract_snippet returns class body for A1' );
like( $extracted_a1, qr/my \$x = 1/, 'extract_snippet contains VarDecl body' );
unlike( $extracted_a1, qr/===/, 'extract_snippet strips the === delimiter line' );

my $extracted_a5 = Oracle->extract_snippet($CORPUS, 'A5');
like( $extracted_a5, qr/:param/, 'extract_snippet returns A5 body with :param' );

# Test 2: wrap_program produces a valid perl program string
my $spec = {
    class       => 'C',
    constructor => { params => {} },
    method      => 'm',
    method_args => [],
    context     => 'scalar',
};

my $program = Oracle->wrap_program($extracted_a1, $spec);
like( $program, qr/use 5\.42\.0/, 'wrapped program has version pragma' );
like( $program, qr/use feature.*class/, 'wrapped program enables class feature' );
like( $program, qr/class C/, 'wrapped program contains the snippet class' );
like( $program, qr/->new/, 'wrapped program instantiates the class' );
like( $program, qr/->m/, 'wrapped program calls the method' );
like( $program, qr/JSON/, 'wrapped program serializes output as JSON' );

# Test 3: wrap_program for A5 includes constructor params
my $spec_a5 = {
    class       => 'C',
    constructor => { params => { x => 42 } },
    method      => 'm',
    method_args => [],
    context     => 'scalar',
};
my $program_a5 = Oracle->wrap_program($extracted_a5, $spec_a5);
like( $program_a5, qr/x.*42|42.*x/, 'A5 wrapped program passes x=>42 to constructor' );

# Test 4: running the wrapped A1 program under perl 5.42 produces JSON output
my ($stdout, $stderr, $exit) = Oracle->run_program($program);
is( $exit, 0, 'wrapped A1 program exits 0' );
unlike( $stdout, qr/^\s*$/, 'wrapped A1 program produces non-empty stdout' );
like( $stdout, qr/return_values/, 'stdout contains return_values key' );

# Test 5: parse_output turns raw JSON output into a hashref
my $parsed = Oracle->parse_output($stdout);
ref_ok( $parsed, 'HASH', 'parse_output returns a hashref' );
ok( exists $parsed->{return_values}, 'parsed output has return_values key' );

# Test 6: full round-trip via capture produces a non-empty BehaviorRecord
my $record = Oracle->capture($extracted_a1, $spec);
isa_ok( $record, ['Chalk::CodeGen::Harness::BehaviorRecord'],
    'full round-trip capture returns BehaviorRecord' );
ok( defined $record->return_values, 'round-trip record has return_values' );
ok( scalar @{ $record->return_values } > 0, 'round-trip record has non-empty return_values' );

done_testing;
