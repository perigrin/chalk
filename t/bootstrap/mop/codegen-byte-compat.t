# ABOUTME: Tests Target::Perl::generate($mop) byte-identical to pre-Phase 4 goldens.
# ABOUTME: Per Phase 4, the MOP-driven codegen preserves determinism vs legacy path.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use File::Glob qw(bsd_glob);
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Perl::Target::Perl;

# Build the grammar pipeline once.
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'pipeline OK') or BAIL_OUT('pipeline');
my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ByteCompatTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::ByteCompatTest::grammar();

# Map golden filename back to source-file path
sub golden_to_source($golden_name) {
    my $stem = $golden_name;
    $stem =~ s{\.pl\.golden$}{};
    $stem =~ s{__}{/}g;
    return "lib/$stem.pm";
}

# Generate via the new MOP-driven path and compare to golden.
sub regenerate($source_path) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $source_path or return undef;
    local $/;
    my $source = <$fh>;
    close $fh;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $result = $parser->parse_value($source);
    return undef unless defined $result && !$result->is_zero();
    return undef unless defined $mop;

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
    return $target->generate($mop);
}

my $goldens_dir = 't/fixtures/codegen-goldens';
my @goldens = sort grep { /\.pl\.golden$/ } map { (split m{/}, $_)[-1] }
    bsd_glob("$goldens_dir/*.pl.golden");
ok(scalar @goldens > 0, 'golden files exist')
    or BAIL_OUT('no goldens captured');

for my $golden_name (@goldens) {
    my $src = golden_to_source($golden_name);
    my $expected;
    {
        open my $fh, '<:utf8', "$goldens_dir/$golden_name"
            or die "Cannot read golden $golden_name: $!";
        local $/;
        $expected = <$fh>;
    }

    my $actual = regenerate($src);
    if (!defined $actual) {
        fail("$golden_name: generate(\$mop) for $src produced undef");
        next;
    }

    # generate($mop) returns HashRef[Str]; the per-source emitted code
    # should land under a key matching this source. Allow any matching
    # entry whose value matches.
    if (ref($actual) eq 'HASH') {
        my @candidates = values $actual->%*;
        my $matched = grep { $_ eq $expected } @candidates;
        ok($matched, "$golden_name: MOP-generated output matches golden")
            or do {
                # Show first 200 chars of the closest non-matching candidate
                # so a diff is locatable.
                my $cand = $candidates[0] // '<no candidates>';
                my $head = substr($cand, 0, 200);
                diag("first candidate head: $head");
            };
    } else {
        # Legacy path: generate returned a plain string. Compare directly.
        is($actual, $expected,
            "$golden_name: generated output matches golden");
    }
}

done_testing();
