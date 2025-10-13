#!/usr/bin/env perl
# ABOUTME: Trace the grammar path differences between function and method calls
# ABOUTME: Show why f($x->y) works but $a->f($x->y) fails
use 5.42.0;
use lib 'lib';

print "GRAMMAR PATH ANALYSIS\n";
print "=" x 70, "\n\n";

print "Function call: f(\$c->d)\n";
print "-" x 70, "\n";
print "Program => StatementList => Statement => BaseStatement\n";
print "  => BlockLevelExpression => Expression => ... => Value\n";
print "  => FunctionCall => 'f', '(', ParameterList, ')'\n";
print "    => Inside ParameterList:\n";
print "      => ExpressionList => Expression => ... => ExprArrow\n";
print "        => ExprValue, ArrowChain => \$c, (->d)\n";
print "      => ExprArrow COMPLETES\n";
print "      => Expression COMPLETES\n";
print "      => ExpressionList COMPLETES\n";
print "      => ParameterList COMPLETES\n";
print "    => FunctionCall scans ')' [OK]\n\n";

print "Method call: \$a->f(\$c->d)\n";
print "-" x 70, "\n";
print "Program => StatementList => Statement => BaseStatement\n";
print "  => BlockLevelExpression => Expression => ... => ExprArrow\n";
print "  => ExprValue, ArrowChain => \$a, (->f(...))\n";
print "    => ArrowChain => OpArrow, ArrowRHS, [ArrowChain]\n";
print "      => ArrowRHS => 'f', '(', ParameterList, ')'\n";
print "        => Inside ParameterList:\n";
print "          => ExpressionList => Expression => ... => ExprArrow\n";
print "            => ExprValue, ArrowChain => \$c, (->d)\n";
print "            => *** NESTED ArrowChain! ***\n";
print "            => Inner ArrowChain tries to continue: ->d, [ArrowChain?]\n";
print "            => Sees ')' - not '->', so continuation fails\n";
print "            => Termination rule: ->d [SHOULD work]\n";
print "          => But OUTER ArrowChain is ALSO active!\n";
print "          => Parser confusion: Which ArrowChain level?\n";
print "        => ParameterList never completes?\n";
print "      => ArrowRHS can't scan ')' [FAIL]\n\n";

print "KEY DIFFERENCE:\n";
print "-" x 70, "\n";
print "FunctionCall: NO ArrowChain context when parsing parameters\n";
print "ArrowRHS:     INSIDE ArrowChain when parsing parameters (NESTED!)\n\n";

print "The grammar structure:\n";
print "-" x 70, "\n";
print "[ 'FunctionCall' => [ 'Identifier', '(', 'ParameterList', ')' ] ]\n";
print "[ 'ArrowRHS'     => [ 'Identifier', '(', 'ParameterList', ')' ] ]\n";
print "[ 'ArrowChain'   => [ 'OpArrow', 'ArrowRHS', 'ArrowChain' ] ]  <- RIGHT-RECURSIVE!\n";
print "[ 'ArrowChain'   => [ 'OpArrow', 'ArrowRHS' ] ]\n\n";

print "When ArrowRHS contains ParameterList, which contains Expression,\n";
print "which contains ArrowChain, we get NESTED right-recursion!\n";
