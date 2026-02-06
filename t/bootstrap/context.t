# ABOUTME: Tests for Chalk::Bootstrap::Context basic comonad with extract only.
# ABOUTME: Validates extract operation for Phase 1a (defer extend/duplicate to Phase 2b).
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Context;

# Test 1: Create context with simple scalar value
{
    my $ctx = Chalk::Bootstrap::Context->new(focus => 42);
    isa_ok($ctx, 'Chalk::Bootstrap::Context');
    is($ctx->extract(), 42, "extract returns focus value");
}

# Test 2: Create context with undef focus (for Boolean semiring)
{
    my $ctx = Chalk::Bootstrap::Context->new(focus => undef);
    isa_ok($ctx, 'Chalk::Bootstrap::Context');
    is($ctx->extract(), undef, "extract returns undef focus");
}

# Test 3: Create context with hashref value (simulating IR node)
{
    my $ir_node = {
        type  => 'MakeSymbol',
        value => 'Identifier',
    };

    my $ctx = Chalk::Bootstrap::Context->new(focus => $ir_node);
    my $extracted = $ctx->extract();

    is_deeply($extracted, $ir_node, "extract returns IR node hashref");
    is(refaddr($extracted), refaddr($ir_node), "extract returns same reference");
}

# Test 4: Create context with blessed object
{
    my $obj = bless { x => 1, y => 2 }, 'Point';
    my $ctx = Chalk::Bootstrap::Context->new(focus => $obj);

    my $extracted = $ctx->extract();
    isa_ok($extracted, 'Point');
    is(refaddr($extracted), refaddr($obj), "extract returns same object");
}

# Test 5: Create context with true boolean
{
    my $ctx = Chalk::Bootstrap::Context->new(focus => true);
    is($ctx->extract(), true, "extract returns true boolean");
}

# Test 6: Create context with false boolean
{
    my $ctx = Chalk::Bootstrap::Context->new(focus => false);
    is($ctx->extract(), false, "extract returns false boolean");
}

# Test 7: Multiple extracts return same value
{
    my $value = "test string";
    my $ctx = Chalk::Bootstrap::Context->new(focus => $value);

    my $first = $ctx->extract();
    my $second = $ctx->extract();

    is($first, $second, "multiple extracts return same value");
    is($first, $value, "extracted value equals original");
}

# Test 8: Context is immutable (extract doesn't modify)
{
    my $array = [1, 2, 3];
    my $ctx = Chalk::Bootstrap::Context->new(focus => $array);

    my $extracted = $ctx->extract();
    push $extracted->@*, 4;

    my $extracted_again = $ctx->extract();
    is(scalar $extracted_again->@*, 4, "context returns same reference (not a copy)");
    # Note: Context doesn't deep-copy, but it also doesn't modify the focus itself
}

# Test 9: Can create multiple contexts with different focus values
{
    my $ctx1 = Chalk::Bootstrap::Context->new(focus => "first");
    my $ctx2 = Chalk::Bootstrap::Context->new(focus => "second");

    is($ctx1->extract(), "first", "first context has first value");
    is($ctx2->extract(), "second", "second context has second value");
}

# Test 10: Context with complex nested structure
{
    my $complex = {
        rule => 'Element',
        children => [
            { type => 'terminal', value => 'Identifier' },
            { type => 'terminal', value => 'Quantifier', quantifier => '?' },
        ],
        position => 42,
    };

    my $ctx = Chalk::Bootstrap::Context->new(focus => $complex);
    my $extracted = $ctx->extract();

    is_deeply($extracted, $complex, "extract returns complex structure");
    is($extracted->{rule}, 'Element', "can access nested fields");
    is(scalar $extracted->{children}->@*, 2, "can access nested arrays");
}

done_testing();
