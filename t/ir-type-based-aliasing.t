#!/usr/bin/env perl
# ABOUTME: Tests type-based alias analysis for context labels
# ABOUTME: Verifies different types use separate namespaces preventing false aliasing
use 5.42.0;
use lib 'lib';
use Test::More tests => 6;
use Chalk::IR::Context;

# Test 1: Same variable name with different types creates different labels
{
    my $int_label = Chalk::IR::Context->make_typed_label('lexical', 'Int', '$x');
    my $str_label = Chalk::IR::Context->make_typed_label('lexical', 'Str', '$x');

    isnt($int_label, $str_label, 'Int and Str variables with same name have different labels');
    like($int_label, qr/Int/, 'Int label contains type');
    like($str_label, qr/Str/, 'Str label contains type');
}

# Test 2: Same type, same name = same label (can alias)
{
    my $label1 = Chalk::IR::Context->make_typed_label('lexical', 'Int', '$x');
    my $label2 = Chalk::IR::Context->make_typed_label('lexical', 'Int', '$x');

    is($label1, $label2, 'Same type and name produce identical labels');
}

# Test 3: Context isolation via type namespaces
{
    my $ctx = Chalk::IR::Context->empty_context();

    # Store Int value at lexical:Int:$x
    my $int_label = Chalk::IR::Context->make_typed_label('lexical', 'Int', '$x');
    $ctx = Chalk::IR::Context->extend_context($ctx, $int_label, 42);

    # Store Str value at lexical:Str:$x
    my $str_label = Chalk::IR::Context->make_typed_label('lexical', 'Str', '$x');
    $ctx = Chalk::IR::Context->extend_context($ctx, $str_label, 'hello');

    # Both values coexist without aliasing
    is($ctx->($int_label), 42, 'Int value stored correctly');
    is($ctx->($str_label), 'hello', 'Str value stored correctly (no aliasing)');
}
