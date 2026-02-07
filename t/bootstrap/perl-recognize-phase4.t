# ABOUTME: Phase 4 test — expression recognition with the Perl grammar.
# ABOUTME: Tests unary, binary, postfix, ternary, assignment expressions and postfix modifiers.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;

# Build the Perl grammar recognizer with Program as start symbol
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Phase4/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::Phase4::grammar();
    my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');

    skip 'Recognizer not built', 1 unless defined $recognizer;

    # §17 AssignmentExpression — basic assignment
    ok($recognizer->parse('$x = 1;'),
        'Phase 4: accepts basic assignment');
    ok($recognizer->parse('$x = $y;'),
        'Phase 4: accepts variable-to-variable assignment');

    # §17 AssignmentExpression — compound assignment operators
    ok($recognizer->parse('$x += 1;'),
        'Phase 4: accepts += assignment');
    ok($recognizer->parse('$x //= $default;'),
        'Phase 4: accepts //= assignment');
    ok($recognizer->parse('$x .= $suffix;'),
        'Phase 4: accepts .= assignment');
    ok($recognizer->parse('$x &&= $val;'),
        'Phase 4: accepts &&= assignment');
    ok($recognizer->parse('$x ||= $val;'),
        'Phase 4: accepts ||= assignment');

    # §14 UnaryExpression
    ok($recognizer->parse('!$x;'),
        'Phase 4: accepts ! unary');
    ok($recognizer->parse('-$x;'),
        'Phase 4: accepts - unary');
    ok($recognizer->parse('+$x;'),
        'Phase 4: accepts + unary');
    ok($recognizer->parse('~$x;'),
        'Phase 4: accepts ~ unary (bitwise complement)');
    ok($recognizer->parse('\\@array;'),
        'Phase 4: accepts \\ reference constructor');
    ok($recognizer->parse('not $x;'),
        'Phase 4: accepts not keyword unary');

    # §15 BinaryExpression — arithmetic
    ok($recognizer->parse('$a + $b;'),
        'Phase 4: accepts + binary');
    ok($recognizer->parse('$a - $b;'),
        'Phase 4: accepts - binary');
    ok($recognizer->parse('$a * $b;'),
        'Phase 4: accepts * binary');
    ok($recognizer->parse('$a / $b;'),
        'Phase 4: accepts / binary');
    ok($recognizer->parse('$a % $b;'),
        'Phase 4: accepts % binary');
    ok($recognizer->parse('$a ** $b;'),
        'Phase 4: accepts ** binary');

    # §15 BinaryExpression — string and repetition
    ok($recognizer->parse('$a . $b;'),
        'Phase 4: accepts . concatenation');
    ok($recognizer->parse('$a x 3;'),
        'Phase 4: accepts x repetition');

    # §15 BinaryExpression — comparison
    ok($recognizer->parse('$a == $b;'),
        'Phase 4: accepts == comparison');
    ok($recognizer->parse('$a != $b;'),
        'Phase 4: accepts != comparison');
    ok($recognizer->parse('$a < $b;'),
        'Phase 4: accepts < comparison');
    ok($recognizer->parse('$a > $b;'),
        'Phase 4: accepts > comparison');
    ok($recognizer->parse('$a <= $b;'),
        'Phase 4: accepts <= comparison');
    ok($recognizer->parse('$a >= $b;'),
        'Phase 4: accepts >= comparison');
    ok($recognizer->parse('$a <=> $b;'),
        'Phase 4: accepts <=> comparison');
    ok($recognizer->parse('$a eq $b;'),
        'Phase 4: accepts eq comparison');
    ok($recognizer->parse('$a ne $b;'),
        'Phase 4: accepts ne comparison');
    ok($recognizer->parse('$obj isa Foo;'),
        'Phase 4: accepts isa operator');

    # §15 BinaryExpression — logical
    ok($recognizer->parse('$a && $b;'),
        'Phase 4: accepts && logical and');
    ok($recognizer->parse('$a || $b;'),
        'Phase 4: accepts || logical or');
    ok($recognizer->parse('$a // $b;'),
        'Phase 4: accepts // defined-or');
    ok($recognizer->parse('$a and $b;'),
        'Phase 4: accepts and keyword');
    ok($recognizer->parse('$a or $b;'),
        'Phase 4: accepts or keyword');

    # §15 BinaryExpression — regex binding
    ok($recognizer->parse('$str =~ /pattern/;'),
        'Phase 4: accepts =~ regex binding');
    ok($recognizer->parse('$str !~ /pattern/;'),
        'Phase 4: accepts !~ negated regex binding');

    # §15 BinaryExpression — range
    ok($recognizer->parse('1 .. 10;'),
        'Phase 4: accepts .. range');
    ok($recognizer->parse('1 ... 10;'),
        'Phase 4: accepts ... yada range');

    # §15 BinaryExpression — bitwise
    ok($recognizer->parse('$a & $b;'),
        'Phase 4: accepts & bitwise and');
    ok($recognizer->parse('$a | $b;'),
        'Phase 4: accepts | bitwise or');
    ok($recognizer->parse('$a ^ $b;'),
        'Phase 4: accepts ^ bitwise xor');
    ok($recognizer->parse('$a << $b;'),
        'Phase 4: accepts << left shift');
    ok($recognizer->parse('$a >> $b;'),
        'Phase 4: accepts >> right shift');

    # §15 BinaryExpression — multi-operator (ambiguous without precedence semiring)
    # Boolean semiring accepts ALL valid parses, so these should all accept
    ok($recognizer->parse('$a + $b * $c;'),
        'Phase 4: accepts mixed arithmetic (ambiguous)');
    ok($recognizer->parse('$a && $b || $c;'),
        'Phase 4: accepts mixed logical (ambiguous)');

    # §12 Parenthesized expression overriding precedence
    ok($recognizer->parse('($a + $b) * $c;'),
        'Phase 4: accepts parenthesized expression');

    # §16 PostfixExpression — MethodCall
    ok($recognizer->parse('$obj->method();'),
        'Phase 4: accepts method call with parens');
    ok($recognizer->parse('$obj->method;'),
        'Phase 4: accepts method call without parens');
    ok($recognizer->parse('$obj->method($a, $b);'),
        'Phase 4: accepts method call with args');
    ok($recognizer->parse("\$class->new(name => 'foo');"),
        'Phase 4: accepts constructor-style method call');

    # §16 PostfixExpression — Subscript
    ok($recognizer->parse('$array->[$i];'),
        'Phase 4: accepts arrow array subscript');
    ok($recognizer->parse('$hash->{$key};'),
        'Phase 4: accepts arrow hash subscript');
    ok($recognizer->parse('$ref->($arg);'),
        'Phase 4: accepts coderef call');
    ok($recognizer->parse('$arr[$i];'),
        'Phase 4: accepts direct array subscript');
    ok($recognizer->parse('$hash{$key};'),
        'Phase 4: accepts direct hash subscript');

    # §16 PostfixExpression — PostfixDeref
    ok($recognizer->parse('$ref->@*;'),
        'Phase 4: accepts postfix array deref');
    ok($recognizer->parse('$ref->%*;'),
        'Phase 4: accepts postfix hash deref');
    ok($recognizer->parse('$ref->$*;'),
        'Phase 4: accepts postfix scalar deref');

    # §16 PostfixExpression — CallExpression
    ok($recognizer->parse('defined($x);'),
        'Phase 4: accepts function call with parens');
    ok($recognizer->parse("join(', ', \@parts);"),
        'Phase 4: accepts function call with multiple args');
    ok($recognizer->parse('push @arr, $val;'),
        'Phase 4: accepts list-style function call');

    # §16 PostfixExpression — CallExpression with block
    # CallExpression with block: grammar requires semicolons inside blocks,
    # so map/grep blocks need statement-terminating semicolons.
    ok($recognizer->parse('map { 1; } @list;'),
        'Phase 4: accepts map with block');
    ok($recognizer->parse('grep { defined; } @items;'),
        'Phase 4: accepts grep with block');

    # §16 PostfixIncDec
    ok($recognizer->parse('$x++;'),
        'Phase 4: accepts postfix increment');
    ok($recognizer->parse('$x--;'),
        'Phase 4: accepts postfix decrement');

    # §17 TernaryExpression
    ok($recognizer->parse('$x ? $y : $z;'),
        'Phase 4: accepts ternary expression');

    # §4 PostfixModifier
    ok($recognizer->parse('return $x if $cond;'),
        'Phase 4: accepts if postfix modifier');
    ok($recognizer->parse('next unless defined($x);'),
        'Phase 4: accepts unless postfix modifier');
    ok($recognizer->parse('push @arr, $val for @items;'),
        'Phase 4: accepts for postfix modifier');

    # Negative cases
    # NOTE: Keywords are NOT reserved. These test structural incompleteness.
    ok(!$recognizer->parse('$a +;'),
        'Phase 4: rejects binary op without right operand');
    ok(!$recognizer->parse('-> method;'),
        'Phase 4: rejects arrow without left operand');
    ok(!$recognizer->parse('$x ? $y;'),
        'Phase 4: rejects incomplete ternary');
    ok(!$recognizer->parse('$obj->[$i'),
        'Phase 4: rejects unclosed subscript');
}

done_testing();
