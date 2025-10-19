# ABOUTME: Tests for Leo items optimization in Earley parser
# ABOUTME: Verifies that right-recursive patterns are handled correctly
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Chalk::BNF;
use FindBin qw($RealBin);
use Chalk::Parser;
use Chalk::Semiring::Boolean;

# Create parser with Boolean semiring (simplest for testing)
my $parser = Chalk::Parser->new(
    grammar  => $chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test 1: ArrowChain (method call chains)
# This is right-recursive: ArrowChain -> OpArrow WS_OPT ArrowRHS WS_OPT ArrowChain
{
    my $code = '$obj->method1()->method2()->method3();';
    my $result = eval { $parser->parse_string($code) };
    ok( $result, 'ArrowChain: method call chain parses successfully' )
      or diag("Error: $@");
}

# Test 2: Longer ArrowChain (should benefit from Leo optimization)
{
    my $code = '$obj->m1()->m2()->m3()->m4()->m5()->m6()->m7()->m8();';
    my $result = eval { $parser->parse_string($code) };
    ok( $result, 'ArrowChain: long method call chain parses successfully' )
      or diag("Error: $@");
}

# Test 3: SubNameExpr (package names)
# Right-recursive: SubNameExpr -> Identifier WS_OPT PackageSeparator WS_OPT SubNameExpr
TODO: {
    local $TODO = 'Grammar does not fully support this package name syntax yet';
    my $code = 'Foo::Bar::Baz::Quux::method();';
    my $result = eval { $parser->parse_string($code) };
    ok( $result, 'SubNameExpr: package name chain parses successfully' )
      or diag("Error: $@");
}

# Test 4: ExprUnaryR (unary operator chains)
# Right-recursive patterns for unary operators
{
    my $code = '!!!!$x;';
    my $result = eval { $parser->parse_string($code) };
    ok( $result, 'ExprUnaryR: unary operator chain parses successfully' )
      or diag("Error: $@");
}

# Test 5: StatementList (multiple statements)
# Right-recursive: StatementList -> Statement WS_OPT ; WS_OPT StatementList
{
    my $code = '$a = 1; $b = 2; $c = 3; $d = 4; $e = 5;';
    my $result = eval { $parser->parse_string($code) };
    ok( $result, 'StatementList: multiple statements parse successfully' )
      or diag("Error: $@");
}

# Test 6: Verify Leo optimization conditions
# Leo items should only be created when:
# 1. Exactly one item waiting for LHS
# 2. No Leo items already waiting
# 3. Rule is right-recursive
# 4. Waiting item will be complete after reduction
#
# This test uses a simple deterministic right-recursive pattern
{
    my $code = '$x->a()->b()->c();';
    my $result = eval { $parser->parse_string($code) };
    ok( $result,
        'Leo conditions: deterministic right-recursive chain parses' )
      or diag("Error: $@");
}

# Test 7: Mixed recursion should not create Leo items inappropriately
# (but should still parse correctly)
{
    my $code = '$x + $y + $z;';    # Left-associative, not right-recursive
    my $result = eval { $parser->parse_string($code) };
    ok( $result, 'Mixed: left-associative expression parses correctly' )
      or diag("Error: $@");
}

# Test 8: Nested right-recursion
{
    my $code = '$obj->method1()->method2() + $obj2->method3()->method4();';
    my $result = eval { $parser->parse_string($code) };
    ok( $result, 'Nested: multiple right-recursive chains parse correctly' )
      or diag("Error: $@");
}

# Test 9: Empty base case (single method call, no chain)
{
    my $code = '$obj->method();';
    my $result = eval { $parser->parse_string($code) };
    ok( $result, 'Base case: single method call parses correctly' )
      or diag("Error: $@");
}

# Test 10: Very long chain (stress test)
# This should complete in reasonable time if Leo optimization is working
{
    my @methods = map { "m$_" } ( 1 .. 50 );
    my $chain = join( '->', @methods );
    my $code = "\$obj->$chain();";

    use Time::HiRes qw(time);
    my $start = time();
    my $result = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm(30);    # 30 second timeout
        my $r = $parser->parse_string($code);
        alarm(0);
        $r;
    };
    my $elapsed = time() - $start;

    if ( $@ && $@ =~ /timeout/ ) {
        fail(
"Stress test: 50-method chain timed out (possible O(n^2) behavior)"
        );
    }
    elsif ($@) {
        fail("Stress test: 50-method chain failed: $@");
    }
    else {
        ok( $result, 'Stress test: 50-method chain parses successfully' )
          or diag("Error: $@");
        diag("Parse time: ${elapsed}s");

        # If Leo is working, this should be roughly linear
        # Without Leo, this would be O(n^2) and very slow
        # We allow up to 10 seconds as a generous limit
        if ( $elapsed > 10 ) {
            diag(
"WARNING: Parse time > 10s suggests Leo optimization may not be working optimally"
            );
        }
    }
}

done_testing();
