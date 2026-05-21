# ABOUTME: Shared test utilities for Perl target compilation tests across tiers.
# ABOUTME: Exports helpers for grammar setup, file parsing to Perl code, and eval with namespace rewriting.
use 5.42.0;
use utf8;

package TestPerlHelpers;

use Exporter 'import';
our @EXPORT_OK = qw(setup_perl_grammar parse_and_generate parse_file_with_cfg eval_module);

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Perl::Target::Perl;

my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();

# Sets up the grammar pipeline for Perl target tests.
# Delegates to the same logic as setup_xs_grammar — they are identical.
sub setup_perl_grammar($namespace) {
    # Reuse the XS helper's setup since the grammar setup is the same
    require TestXSHelpers;
    return TestXSHelpers::setup_xs_grammar($namespace);
}

# Parses a .pm file and returns ($ir, $sa, $sem_ctx) for cfg-aware generation.
# Returns () on failure.
sub parse_file_with_cfg($gen_grammar, $file) {
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;
    close $fh;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    my $result = $parser->parse_value($source);
    return unless defined $result;

    my $sa = $semiring->semirings()->[-1];  # SA is always last
    my $sem_ctx = $result;
    return unless defined $sem_ctx;
    my $ir = $sem_ctx->extract();
    return unless defined $ir;

    return ($ir, $sa, $sem_ctx);
}

# Parses a .pm file and generates Perl code from the IR using cfg_state dispatch.
# Returns the generated Perl code string or undef on failure.
sub parse_and_generate($gen_grammar, $file) {
    my ($ir, $sa, $sem_ctx) = parse_file_with_cfg($gen_grammar, $file);
    return unless defined $ir;

    return $perl_target->_generate_with_cfg($ir, $sa, $sem_ctx);
}

# Evals generated Perl code with namespace rewriting.
# $code: generated Perl source
# $original_ns: original namespace to replace (e.g., 'Chalk::Bootstrap::Foo')
# $test_ns: test namespace to replace with (e.g., 'Chalk::Bootstrap::FooGenerated')
# Returns ($success, $error). $success is true if eval succeeds.
sub eval_module($code, $original_ns, $test_ns) {
    my $renamed = $code;
    $renamed =~ s/\Q$original_ns\E\b/$test_ns/g;
    my $ok = eval "$renamed; 1";
    if (!$ok) {
        return (false, $@);
    }
    return (true, undef);
}
