# ABOUTME: Unit tests for Target::XS code emitter.
# ABOUTME: Tests XS generation from IR nodes including scaffold, lowering, and full pipeline.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

# === Scaffold Tests ===

# Test: Module loads
use_ok('Chalk::Bootstrap::Target::XS');

# Test: isa Target
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    isa_ok($target, 'Chalk::Bootstrap::Target');
    isa_ok($target, 'Chalk::Bootstrap::Target::XS');
}

# Test: generate([]) returns a string with preamble and module declaration
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $output = $target->generate([]);
    like($output, qr/#define PERL_NO_GET_CONTEXT/, 'scaffold contains PERL_NO_GET_CONTEXT');
    like($output, qr/#include "EXTERN\.h"/, 'scaffold contains EXTERN.h');
    like($output, qr/#include "perl\.h"/, 'scaffold contains perl.h');
    like($output, qr/#include "XSUB\.h"/, 'scaffold contains XSUB.h');
    like($output, qr/MODULE = Chalk::Grammar::BNF::Rules/, 'scaffold contains MODULE =');
    like($output, qr/PACKAGE = Chalk::Grammar::BNF::Rules/, 'scaffold contains PACKAGE =');
}

# Test: module_name is configurable
{
    my $target = Chalk::Bootstrap::Target::XS->new(module_name => 'Test::Module');
    my $output = $target->generate([]);
    like($output, qr/MODULE = Test::Module/, 'configurable module name in MODULE =');
    like($output, qr/PACKAGE = Test::Module/, 'configurable module name in PACKAGE =');
    is($target->module_name(), 'Test::Module', 'module_name reader works');
}

# Test: generate(undef) dies with useful error
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    eval { $target->generate(undef) };
    like($@, qr/generate\(\) requires an arrayref/, 'generate(undef) dies with useful error');
}

# Test: generate("not an array") dies with useful error
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    eval { $target->generate("not an array") };
    like($@, qr/generate\(\) requires an arrayref/, 'generate(non-arrayref) dies with useful error');
}

# === C String Escaping Tests ===

{
    my $target = Chalk::Bootstrap::Target::XS->new();

    # Plain string — no escaping needed
    is($target->_escape_c_string('hello'), 'hello', 'plain string passes through');

    # Backslash → double backslash
    is($target->_escape_c_string('a\\b'), 'a\\\\b', 'backslash is doubled');

    # Double quote → backslash double quote
    is($target->_escape_c_string('say "hi"'), 'say \\"hi\\"', 'double quotes are escaped');

    # Combined: both backslash and double quote
    is($target->_escape_c_string('a\\"b'), 'a\\\\\\"b', 'combined backslash and double quote');

    # Complex regex pattern from BNF meta-grammar
    # Input: (?:\s|#[^\n]*)* — contains backslashes
    is($target->_escape_c_string('(?:\\s|#[^\\n]*)*'),
       '(?:\\\\s|#[^\\\\n]*)*',
       'complex regex pattern escaping');

    # Control characters: actual newline byte → \n in C
    is($target->_escape_c_string("line1\nline2"), 'line1\\nline2',
        'actual newline byte escaped to \\n');

    # Control characters: actual tab byte → \t in C
    is($target->_escape_c_string("col1\tcol2"), 'col1\\tcol2',
        'actual tab byte escaped to \\t');

    # Control characters: actual carriage return → \r in C
    is($target->_escape_c_string("line1\rline2"), 'line1\\rline2',
        'actual carriage return escaped to \\r');

    # Null byte → \0 in C
    is($target->_escape_c_string("before\0after"), 'before\\0after',
        'null byte escaped to \\0');
}

# === Terminal Delimiter Stripping ===

{
    my $target = Chalk::Bootstrap::Target::XS->new();

    # Strip / delimiters from terminal value
    is($target->_strip_terminal_delimiters('/[A-Z]+/'), '[A-Z]+',
        'strips / delimiters from terminal');

    # Non-delimited value passes through
    is($target->_strip_terminal_delimiters('::='), '::=',
        'non-delimited value passes through');

    # Value that starts with / but does not end with / passes through
    is($target->_strip_terminal_delimiters('/foo'), '/foo',
        'incomplete delimiters pass through');

    # Complex regex terminal
    is($target->_strip_terminal_delimiters('/(?:\\s|#[^\\n]*)*$/'),
        '(?:\\s|#[^\\n]*)*$',
        'complex regex terminal strips delimiters');
}

# === Constant Node Lowering ===

use Chalk::Bootstrap::IR::NodeFactory;

{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $target = Chalk::Bootstrap::Target::XS->new();

    # String constant → newSVpvs
    my $const = $factory->make('Constant', const_type => 'string', value => 'Grammar');
    is($target->_emit_constant($const), 'newSVpvs("Grammar")',
        'string constant emits newSVpvs');

    # Enum constant → newSVpvs (type names are strings too)
    my $enum = $factory->make('Constant', const_type => 'enum', value => 'reference');
    is($target->_emit_constant($enum), 'newSVpvs("reference")',
        'enum constant emits newSVpvs');

    # String with double quotes → escaped in C
    my $quoted = $factory->make('Constant', const_type => 'string', value => 'say "hi"');
    is($target->_emit_constant($quoted), 'newSVpvs("say \\"hi\\"")',
        'constant with double quotes is escaped');

    # String with backslash → escaped in C
    my $bslash = $factory->make('Constant', const_type => 'string', value => 'a\\b');
    is($target->_emit_constant($bslash), 'newSVpvs("a\\\\b")',
        'constant with backslash is escaped');
}

# === Symbol Construction Lowering ===

# Helper: build a Constructor:Symbol IR node (same as codegen-perl.t)
sub make_symbol {
    my (%args) = @_;
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $type = $factory->make('Constant', const_type => 'enum', value => $args{type});
    my $value = $factory->make('Constant', const_type => 'string', value => $args{value});
    my $quant = $factory->make('Constant', const_type => 'string', value => $args{quantifier});
    return $factory->make('Constructor',
        class => 'Symbol',
        type => $type,
        value => $value,
        quantifier => $quant,
    );
}

# Test: Reference symbol without quantifier
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'reference', value => 'Atom', quantifier => undef);

    my $nodes = $target->_emit_symbol($sym, 'sym_0');
    is(ref($nodes), 'ARRAY', '_emit_symbol returns arrayref');
    is(scalar $nodes->@*, 2, '_emit_symbol returns 2 nodes (VarDecl + Statement)');

    # First node is a VarDecl
    isa_ok($nodes->[0], 'Chalk::Bootstrap::Target::XS::AST::VarDecl');
    is($nodes->[0]->type(), 'SV *', 'VarDecl type is SV *');
    is($nodes->[0]->name(), 'sym_0', 'VarDecl name matches var_name arg');

    # Second node is a Statement with call_method block
    isa_ok($nodes->[1], 'Chalk::Bootstrap::Target::XS::AST::Statement');
    my $code = $nodes->[1]->code();
    like($code, qr/dSP/, 'call_method block has dSP');
    like($code, qr/ENTER; SAVETMPS/, 'call_method block has ENTER; SAVETMPS');
    like($code, qr/Chalk::Grammar::Symbol/, 'block pushes Symbol class name');
    like($code, qr/"type"/, 'block pushes type key');
    like($code, qr/"reference"/, 'block pushes reference type value');
    like($code, qr/"value"/, 'block pushes value key');
    like($code, qr/"Atom"/, 'block pushes Atom value');
    unlike($code, qr/quantifier/, 'block omits quantifier when undef');
    like($code, qr/call_method\("new", G_SCALAR\)/, 'block calls new');
    like($code, qr/sym_0 = SvREFCNT_inc\(POPs\)/, 'block assigns to sym_0');
    like($code, qr/FREETMPS; LEAVE/, 'block has FREETMPS; LEAVE');
}

# Test: Terminal symbol — value has delimiters stripped and C-escaped
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Z]+/', quantifier => undef);

    my $nodes = $target->_emit_symbol($sym, 'sym_1');
    my $code = $nodes->[1]->code();
    like($code, qr/"terminal"/, 'terminal symbol has correct type');
    like($code, qr/"\[A-Z\]\+"/, 'terminal value has delimiters stripped');
    unlike($code, qr/\/\[A-Z\]\+\//, 'terminal value does not have / delimiters');
}

# Test: Symbol with quantifier — block includes quantifier args
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'reference', value => 'Rule', quantifier => '+');

    my $nodes = $target->_emit_symbol($sym, 'sym_2');
    my $code = $nodes->[1]->code();
    like($code, qr/"quantifier"/, 'block includes quantifier key');
    like($code, qr/"\+"/, 'block includes + quantifier value');
}

# Test: Complex regex terminal — properly escaped in C string
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/(?:\\s|#[^\\n]*)*/');

    my $nodes = $target->_emit_symbol($sym, 'sym_3');
    my $code = $nodes->[1]->code();
    # After stripping delimiters: (?:\s|#[^\n]*)*
    # After C escaping: (?:\\s|#[^\\n]*)*
    like($code, qr/\\\\s/, 'complex regex has escaped backslash-s');
    like($code, qr/\\\\n/, 'complex regex has escaped backslash-n');
}

# === Expression Construction Lowering ===

# Helper: build a Constructor:Expression IR node from symbols
sub make_expression {
    my (@symbols) = @_;
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    return $factory->make('Constructor',
        class => 'Expression',
        elements => \@symbols,
    );
}

# Helper: build a Constructor:Rule IR node
sub make_rule {
    my ($name, @expressions) = @_;
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $name_node = $factory->make('Constant', const_type => 'string', value => $name);
    return $factory->make('Constructor',
        class => 'Rule',
        name => $name_node,
        expressions => \@expressions,
    );
}

# Test: Single-symbol expression lowering
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'reference', value => 'Identifier', quantifier => undef);
    my $expr = make_expression($sym);

    my $nodes = $target->_emit_expression($expr, 'expr_0');
    is(ref($nodes), 'ARRAY', '_emit_expression returns arrayref');

    # Should have: VarDecl(AV *expr_0), Statement(expr_0 = newAV()),
    #   symbol VarDecl, symbol Statement, Statement(av_push)
    ok(scalar $nodes->@* >= 4, '_emit_expression returns at least 4 nodes');

    # First node: VarDecl for AV *expr_0
    isa_ok($nodes->[0], 'Chalk::Bootstrap::Target::XS::AST::VarDecl');
    is($nodes->[0]->type(), 'AV *', 'expression VarDecl type is AV *');
    is($nodes->[0]->name(), 'expr_0', 'expression VarDecl name is expr_0');

    # Second node: Statement for newAV()
    isa_ok($nodes->[1], 'Chalk::Bootstrap::Target::XS::AST::Statement');
    like($nodes->[1]->code(), qr/expr_0 = newAV\(\)/, 'expression init with newAV()');

    # Last node: av_push statement
    my $last = $nodes->[-1];
    isa_ok($last, 'Chalk::Bootstrap::Target::XS::AST::Statement');
    like($last->code(), qr/av_push\(expr_0/, 'expression av_push to expr_0');
}

# Test: Multi-symbol expression
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym1 = make_symbol(type => 'reference', value => 'Identifier', quantifier => undef);
    my $sym2 = make_symbol(type => 'terminal', value => '/::=/', quantifier => undef);
    my $expr = make_expression($sym1, $sym2);

    my $nodes = $target->_emit_expression($expr, 'expr_0');

    # Count av_push statements (one per symbol)
    my @pushes = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /av_push/
    } $nodes->@*;
    is(scalar @pushes, 2, 'multi-symbol expression has 2 av_push statements');
}

# === Rule Construction Lowering ===

# Test: Single-alternative rule
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Za-z]+/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule('Identifier', $expr);

    my $nodes = $target->_emit_rule($rule);
    is(ref($nodes), 'ARRAY', '_emit_rule returns arrayref');

    # Check for VarDecls: AV *expressions, SV *rule (at minimum)
    my @var_decls = grep { $_ isa Chalk::Bootstrap::Target::XS::AST::VarDecl } $nodes->@*;
    ok(scalar @var_decls >= 2, 'rule has at least 2 VarDecls');

    # Check for expressions = newAV()
    my @init_stmts = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /expressions = newAV/
    } $nodes->@*;
    is(scalar @init_stmts, 1, 'rule has expressions = newAV() statement');

    # Check for av_push to expressions (one per alternative)
    my @expr_pushes = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /av_push\(expressions/
    } $nodes->@*;
    is(scalar @expr_pushes, 1, 'single-alt rule has 1 av_push to expressions');

    # Check for call_method block constructing Rule
    my @rule_blocks = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /Chalk::Grammar::Rule/
    } $nodes->@*;
    is(scalar @rule_blocks, 1, 'rule has call_method block for Rule constructor');

    # Check Rule call_method uses newRV_noinc for expressions
    like($rule_blocks[0]->code(), qr/newRV_noinc/, 'Rule constructor uses newRV_noinc');

    # Check for RETVAL assignment
    my @retval = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /RETVAL = rule/
    } $nodes->@*;
    is(scalar @retval, 1, 'rule has RETVAL = rule statement');

    # Check rule name appears in the call_method block
    like($rule_blocks[0]->code(), qr/"Identifier"/, 'Rule constructor has correct name');
}

# Test: Multi-alternative rule
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym1 = make_symbol(type => 'reference', value => 'Identifier', quantifier => undef);
    my $sym2 = make_symbol(type => 'reference', value => 'InlineRegex', quantifier => undef);
    my $expr1 = make_expression($sym1);
    my $expr2 = make_expression($sym2);
    my $rule = make_rule('Atom', $expr1, $expr2);

    my $nodes = $target->_emit_rule($rule);

    # 2 alternatives → 2 av_pushes to expressions
    my @expr_pushes = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /av_push\(expressions/
    } $nodes->@*;
    is(scalar @expr_pushes, 2, 'multi-alt rule has 2 av_pushes to expressions');
}

# === Counter reset between rules ===

# Test: Symbol/expression counters reset when _emit_rule is called multiple times
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();

    my $sym1 = make_symbol(type => 'reference', value => 'A', quantifier => undef);
    my $expr1 = make_expression($sym1);
    my $rule1 = make_rule('First', $expr1);

    my $sym2 = make_symbol(type => 'reference', value => 'B', quantifier => undef);
    my $expr2 = make_expression($sym2);
    my $rule2 = make_rule('Second', $expr2);

    # First call uses sym_0, expr_0
    $target->_emit_rule($rule1);

    # Second call should also use sym_0, expr_0 (counters reset)
    my $nodes2 = $target->_emit_rule($rule2);

    my @sym_decls = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::VarDecl
        && $_->name() =~ /^sym_/
    } $nodes2->@*;
    is($sym_decls[0]->name(), 'sym_0', 'symbol counter resets between rules');

    my @expr_decls = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::VarDecl
        && $_->name() =~ /^expr_/
    } $nodes2->@*;
    is($expr_decls[0]->name(), 'expr_0', 'expression counter resets between rules');
}

# === newSVpvn for terminal regex values ===

# Test: Terminal regex values use newSVpvn with explicit length
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Z]+/', quantifier => undef);
    my $nodes = $target->_emit_symbol($sym, 'sym_0');
    my $code = $nodes->[1]->code();

    # Terminal values should use newSVpvn with explicit length per spec §5.4
    like($code, qr/newSVpvn\("[^"]+",\s*\d+\)/, 'terminal value uses newSVpvn with length');
}

# Test: Non-terminal values still use newSVpvs
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'reference', value => 'Atom', quantifier => undef);
    my $nodes = $target->_emit_symbol($sym, 'sym_0');
    my $code = $nodes->[1]->code();

    # Reference values use newSVpvs (compile-time sizeof)
    like($code, qr/newSVpvs\("Atom"\)/, 'reference value uses newSVpvs');
}

done_testing();
