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

done_testing();
