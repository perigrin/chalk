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
        type  => 'Symbol',
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

# Test 11: leaves() with single leaf context
{
    my $ctx = Chalk::Bootstrap::Context->new(focus => "leaf value");
    my @leaves = $ctx->leaves();

    is(scalar @leaves, 1, "single leaf context returns self");
    is($leaves[0]->extract(), "leaf value", "leaf has correct focus");
}

# Test 12: leaves() with binary tree of contexts
{
    my $leaf1 = Chalk::Bootstrap::Context->new(focus => "leaf1");
    my $leaf2 = Chalk::Bootstrap::Context->new(focus => "leaf2");
    my $parent = Chalk::Bootstrap::Context->new(
        focus => undef,
        children => [$leaf1, $leaf2],
    );

    my @leaves = $parent->leaves();
    is(scalar @leaves, 2, "binary tree returns two leaves");
    is($leaves[0]->extract(), "leaf1", "first leaf has correct focus");
    is($leaves[1]->extract(), "leaf2", "second leaf has correct focus");
}

# Test 13: leaves() with nested binary tree
{
    my $leaf1 = Chalk::Bootstrap::Context->new(focus => "a");
    my $leaf2 = Chalk::Bootstrap::Context->new(focus => "b");
    my $subtree = Chalk::Bootstrap::Context->new(
        focus => undef,
        children => [$leaf1, $leaf2],
    );

    my $leaf3 = Chalk::Bootstrap::Context->new(focus => "c");
    my $root = Chalk::Bootstrap::Context->new(
        focus => undef,
        children => [$subtree, $leaf3],
    );

    my @leaves = $root->leaves();
    is(scalar @leaves, 3, "nested tree returns three leaves");
    is($leaves[0]->extract(), "a", "first leaf correct");
    is($leaves[1]->extract(), "b", "second leaf correct");
    is($leaves[2]->extract(), "c", "third leaf correct");
}

# Test 14: leaves() with class filter
{
    my $obj1 = bless { value => 1 }, 'NodeA';
    my $obj2 = bless { value => 2 }, 'NodeB';
    my $obj3 = bless { value => 3 }, 'NodeA';

    my $leaf1 = Chalk::Bootstrap::Context->new(focus => $obj1);
    my $leaf2 = Chalk::Bootstrap::Context->new(focus => $obj2);
    my $leaf3 = Chalk::Bootstrap::Context->new(focus => $obj3);

    my $root = Chalk::Bootstrap::Context->new(
        focus => undef,
        children => [$leaf1, $leaf2, $leaf3],
    );

    my @all_leaves = $root->leaves();
    is(scalar @all_leaves, 3, "no filter returns all leaves");

    my @filtered = $root->leaves('NodeA');
    is(scalar @filtered, 2, "class filter returns only NodeA objects");
    is($filtered[0]->extract()->{value}, 1, "first filtered leaf correct");
    is($filtered[1]->extract()->{value}, 3, "second filtered leaf correct");
}

# Test 15: scanned_text() with single string focus
{
    my $ctx = Chalk::Bootstrap::Context->new(focus => "hello");
    is($ctx->scanned_text(), "hello", "single string returns itself");
}

# Test 16: scanned_text() with binary tree of strings
{
    my $leaf1 = Chalk::Bootstrap::Context->new(focus => "hello");
    my $leaf2 = Chalk::Bootstrap::Context->new(focus => " world");
    my $parent = Chalk::Bootstrap::Context->new(
        focus => undef,
        children => [$leaf1, $leaf2],
    );

    is($parent->scanned_text(), "hello world", "concatenates children");
}

# Test 17: scanned_text() with nested tree
{
    my $leaf1 = Chalk::Bootstrap::Context->new(focus => "a");
    my $leaf2 = Chalk::Bootstrap::Context->new(focus => "b");
    my $subtree = Chalk::Bootstrap::Context->new(
        focus => undef,
        children => [$leaf1, $leaf2],
    );

    my $leaf3 = Chalk::Bootstrap::Context->new(focus => "c");
    my $root = Chalk::Bootstrap::Context->new(
        focus => undef,
        children => [$subtree, $leaf3],
    );

    is($root->scanned_text(), "abc", "concatenates deeply nested strings");
}

# Test 18: scanned_text() skips non-string focuses (IR nodes)
{
    my $obj = bless { type => 'IR' }, 'IRNode';
    my $leaf1 = Chalk::Bootstrap::Context->new(focus => "start");
    my $leaf2 = Chalk::Bootstrap::Context->new(focus => $obj);
    my $leaf3 = Chalk::Bootstrap::Context->new(focus => "end");

    my $root = Chalk::Bootstrap::Context->new(
        focus => undef,
        children => [$leaf1, $leaf2, $leaf3],
    );

    is($root->scanned_text(), "startend", "skips object focuses, concatenates strings");
}

# Test 19: scanned_text() with undef focus at leaf
{
    my $leaf1 = Chalk::Bootstrap::Context->new(focus => "text");
    my $leaf2 = Chalk::Bootstrap::Context->new(focus => undef);
    my $parent = Chalk::Bootstrap::Context->new(
        focus => undef,
        children => [$leaf1, $leaf2],
    );

    is($parent->scanned_text(), "text", "treats undef as empty string");
}

# Test 20: leaves() with empty children array
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => undef,
        children => [],
    );

    my @leaves = $ctx->leaves();
    is(scalar @leaves, 0, "empty children returns no leaves");
    is($ctx->scanned_text(), "", "empty children returns empty string");
}

# Test 21: scanned_text() handles deep linear chains without stack overflow
# Regression test: parsing large files creates deep Context trees that caused
# deep recursion warnings in the original recursive implementation.
{
    # Build a linear chain of 1000 single-child nodes — each level recurses once.
    # Perl warns at depth 100, so this triggers the bug with the recursive version.
    my $current = Chalk::Bootstrap::Context->new(focus => "leaf");
    for my $i (1 .. 999) {
        $current = Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [$current],
        );
    }

    # Capture any deep-recursion warnings
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    my $text = $current->scanned_text();

    is($text, "leaf", "deep linear chain returns correct text");
    my @deep_warnings = grep { /Deep recursion/ } @warnings;
    is(scalar @deep_warnings, 0, "no deep recursion warnings for 1000-deep chain");
}

# Test 22: leaves() handles deep linear chains without stack overflow
{
    my $current = Chalk::Bootstrap::Context->new(focus => "deep_leaf");
    for my $i (1 .. 999) {
        $current = Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [$current],
        );
    }

    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    my @leaves = $current->leaves();

    is(scalar @leaves, 1, "deep linear chain returns one leaf");
    is($leaves[0]->extract(), "deep_leaf", "leaf has correct value");
    my @deep_warnings = grep { /Deep recursion/ } @warnings;
    is(scalar @deep_warnings, 0, "no deep recursion warnings for 1000-deep chain");
}

done_testing();
