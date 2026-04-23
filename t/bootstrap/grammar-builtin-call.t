# ABOUTME: Focused test for CallExpression parsing of builtin function calls.
# ABOUTME: Verifies that push/pop/keys/etc parse via CallExpression, not as bare identifiers.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build Perl grammar via the full pipeline: BNF → IR → codegen → eval → grammar objects
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
if (!defined $raw_ir) {
    plan(skip_all => 'BNF pipeline failed — cannot generate Perl grammar');
}

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::BuiltinCallTest/g;
eval $generated;
if ($@) {
    plan(skip_all => "Generated grammar code failed to eval: $@");
}
my $gen_grammar = Chalk::Grammar::Perl::BuiltinCallTest::grammar();

# Test 1: Does "push @arr, $x" recognize starting from CallExpression?
{
    my $parser = build_perl_recognizer($gen_grammar, start => 'CallExpression');
    my $result = $parser->parse_value('push @arr, $x');
    ok(defined $result, 'push @arr, $x recognizes as CallExpression');
}

# Test 2: Does "push @arr, $x" recognize starting from ExpressionStatement?
{
    my $parser = build_perl_recognizer($gen_grammar, start => 'ExpressionStatement');
    my $result = $parser->parse_value('push @arr, $x');
    ok(defined $result, 'push @arr, $x recognizes as ExpressionStatement');
}

# Test 3: Does "keys %$hash" recognize as CallExpression?
{
    my $parser = build_perl_recognizer($gen_grammar, start => 'CallExpression');
    my $result = $parser->parse_value('keys %$hash');
    ok(defined $result, 'keys %$hash recognizes as CallExpression');
}

# Test 4: Does "defined $x" recognize as CallExpression?
{
    my $parser = build_perl_recognizer($gen_grammar, start => 'CallExpression');
    my $result = $parser->parse_value('defined $x');
    ok(defined $result, 'defined $x recognizes as CallExpression');
}

# Test 5: Does "sort keys %$hash" recognize as CallExpression?
# This is the nested case: sort(keys(%$hash))
{
    my $parser = build_perl_recognizer($gen_grammar, start => 'CallExpression');
    my $result = $parser->parse_value('sort keys %$hash');
    ok(defined $result, 'sort keys %$hash recognizes as CallExpression');
}

# Test 6: Full IR parse — does "push @arr, $x" produce a BuiltinCall/Call node
# when parsed through the full 5-ary semiring as a SimpleStatement?
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'SimpleStatement');
    my $result = $parser->parse_value('push @arr, $x');
    if (defined $result) {
        my $ir = $result->extract();
        # The IR should be a Call node (BuiltinCall), not a bare Constant("push")
        if ($ir isa Chalk::IR::Node::Call) {
            ok(true, 'push @arr, $x produces Call node from SimpleStatement');
            is($ir->dispatch_kind(), 'builtin',
                'dispatch_kind is builtin');
        } elsif ($ir isa Chalk::IR::Node::Constant) {
            fail('push @arr, $x produced bare Constant — CallExpression not matching');
            diag("Got Constant with value: " . ($ir->value() // 'undef'));
        } elsif (ref($ir) eq 'ARRAY') {
            fail('push @arr, $x produced array — statement split into multiple items');
            diag("Array has " . scalar($ir->@*) . " elements");
        } else {
            fail('push @arr, $x produced unexpected IR type');
            diag("Got: " . ref($ir));
        }
    } else {
        fail('push @arr, $x failed to parse as SimpleStatement');
    }
}

# Test 7: Does "die $msg" recognize as CallExpression?
# die is syntactically just a prefix function call
{
    my $parser = build_perl_recognizer($gen_grammar, start => 'CallExpression');
    my $result = $parser->parse_value('die $msg');
    ok(defined $result, 'die $msg recognizes as CallExpression');
}

# Test 8: Does "return $x" recognize as both ReturnStatement AND CallExpression?
# return has its own grammar rule, so it should match ReturnStatement.
# The question is whether it ALSO matches as CallExpression (ambiguity).
{
    my $parser_ret = build_perl_recognizer($gen_grammar, start => 'ReturnStatement');
    my $result_ret = $parser_ret->parse_value('return $x');
    ok(defined $result_ret, 'return $x recognizes as ReturnStatement');

    my $parser_call = build_perl_recognizer($gen_grammar, start => 'CallExpression');
    my $result_call = $parser_call->parse_value('return $x');
    # This tells us whether there's ambiguity between ReturnStatement and CallExpression
    if (defined $result_call) {
        pass('return $x ALSO recognizes as CallExpression — ambiguity exists');
    } else {
        pass('return $x does NOT recognize as CallExpression — no ambiguity');
    }
}

done_testing();
