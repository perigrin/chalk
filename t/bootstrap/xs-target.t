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

done_testing();
