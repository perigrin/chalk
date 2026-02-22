# ABOUTME: Shared test utilities for Perl target compilation tests across tiers.
# ABOUTME: Exports helpers for grammar setup, file parsing to Perl code, and eval with namespace rewriting.
use 5.42.0;
use utf8;

package TestPerlHelpers;

use Exporter 'import';
our @EXPORT_OK = qw(setup_perl_grammar parse_and_generate eval_module);

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Perl::Target::Perl;

my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();

# Sets up the grammar pipeline for Perl target tests.
# Accepts a namespace string used to rename the generated grammar module.
# Returns ($gen_grammar) or dies on failure.
sub setup_perl_grammar($namespace) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $raw_ir = perl_pipeline();
    die "perl_pipeline returned undef" unless defined $raw_ir;

    my $bnf_target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $bnf_target->generate($raw_ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/$namespace/g;
    eval $generated;
    die "Grammar eval failed: $@" if $@;

    no strict 'refs';
    my $grammar = "${namespace}::grammar"->();
    die "Grammar not defined after eval" unless defined $grammar;
    return $grammar;
}

# Parses a .pm file and generates Perl code from the IR.
# Returns the generated Perl code string or undef on failure.
sub parse_and_generate($gen_grammar, $file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return unless defined $result;

    my $sem_ctx = $result->[4];
    return unless defined $sem_ctx;
    my $ir = $sem_ctx->extract();
    return unless defined $ir;

    return $perl_target->generate($ir);
}

# Evals generated Perl code with namespace rewriting.
# $code: generated Perl source
# $original_ns: original namespace to replace (e.g., 'Chalk::Bootstrap::Foo')
# $test_ns: test namespace to replace with (e.g., 'Chalk::Bootstrap::FooGenerated')
# Returns ($success, $error). $success is true if eval succeeds.
sub eval_module($code, $original_ns, $test_ns) {
    my $renamed = $code;
    $renamed =~ s/\Q$original_ns\E\b/$test_ns/g;
    eval $renamed;
    if ($@) {
        return (false, $@);
    }
    return (true, undef);
}
