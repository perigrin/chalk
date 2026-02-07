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

done_testing();
