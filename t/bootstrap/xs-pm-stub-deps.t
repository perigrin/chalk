# ABOUTME: Tests that the XS .pm stub includes require statements for pure-Perl deps.
# ABOUTME: Verifies the XS module can load standalone without pre-loading dependencies.
use 5.42.0;
use utf8;
no warnings 'experimental::class';

use Test::More;
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Perl::Target::XS;

# === Test: _emit_pm_stub includes require for runtime deps ===
subtest 'pm stub includes require for runtime deps' => sub {
    my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
        module_name => 'Test::XS::Module',
    );

    # Simulate: these packages are compiled into XS (don't need require)
    my @compiled_classes = (
        'Chalk::Bootstrap::Earley',
        'Chalk::Bootstrap::Semiring::Boolean',
    );

    # Simulate: XS content references these via call_pv
    my $xs_content = <<'XS';
call_pv("Chalk::Bootstrap::Terminal::match", G_SCALAR);
call_pv("Chalk::Grammar::Perl::KeywordTable::is_keyword", G_SCALAR);
call_method("new", G_SCALAR);  // not a call_pv, should be ignored
newSVpvs("Chalk::Bootstrap::Earley");  // compiled class, no require needed
call_pv("Chalk::Bootstrap::Semiring::TypeInferenceActions::reset_method_registry", G_SCALAR);
XS

    my $stub = $xs->_emit_pm_stub_with_deps($xs_content, \@compiled_classes);

    # Should require the non-compiled packages
    like($stub, qr/require Chalk::Bootstrap::Terminal;/,
        'requires Terminal (call_pv dep, not compiled)');
    like($stub, qr/require Chalk::Grammar::Perl::KeywordTable;/,
        'requires KeywordTable (call_pv dep, not compiled)');
    like($stub, qr/require Chalk::Bootstrap::Semiring::TypeInferenceActions;/,
        'requires TypeInferenceActions (call_pv dep, not compiled)');

    # Should NOT require compiled classes
    unlike($stub, qr/require Chalk::Bootstrap::Earley;/,
        'does not require compiled class Earley');
    unlike($stub, qr/require Chalk::Bootstrap::Semiring::Boolean;/,
        'does not require compiled class Boolean');

    # Should still have the standard stub structure
    like($stub, qr/package Test::XS::Module;/, 'has package declaration');
    like($stub, qr/DynaLoader/, 'uses DynaLoader');
    like($stub, qr/_bootstrap/, 'calls _bootstrap');
};

# === Test: requires come before _bootstrap() call ===
subtest 'requires come before bootstrap' => sub {
    my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
        module_name => 'Test::XS::Module',
    );

    my $xs_content = 'call_pv("Chalk::Bootstrap::Terminal::match", G_SCALAR);';
    my $stub = $xs->_emit_pm_stub_with_deps($xs_content, []);

    # Find positions
    my $require_pos = index($stub, 'require Chalk::Bootstrap::Terminal');
    my $bootstrap_pos = index($stub, '_bootstrap()');
    ok($require_pos >= 0, 'require statement exists');
    ok($bootstrap_pos >= 0, 'bootstrap call exists');
    ok($require_pos < $bootstrap_pos,
        'require comes before _bootstrap call');
};

done_testing;
