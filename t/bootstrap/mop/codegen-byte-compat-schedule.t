# ABOUTME: Tests Target::Perl::_generate_from_schedule() byte-identical to existing goldens.
# ABOUTME: Phase 5a — parallel test path for scheduler-driven codegen during integration.
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
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Perl::Target::Perl;

# Build the grammar pipeline once.
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'pipeline OK') or BAIL_OUT('pipeline');
my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ByteCompatScheduleTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::ByteCompatScheduleTest::grammar();

sub golden_to_source($golden_name) {
    my $stem = $golden_name;
    $stem =~ s{\.pl\.golden$}{};
    $stem =~ s{__}{/}g;
    return "lib/$stem.pm";
}

# Generate via the SCHEDULER path (not the legacy MOP synthesis layer).
sub regenerate_via_schedule($source_path) {
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
    return $target->_generate_from_schedule($mop);
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

    my $actual = regenerate_via_schedule($src);
    if (!defined $actual) {
        fail("$golden_name: _generate_from_schedule for $src produced undef");
        next;
    }

    if (ref($actual) eq 'HASH') {
        my @candidates = values $actual->%*;
        my $matched = grep { $_ eq $expected } @candidates;
        ok($matched, "$golden_name: schedule-generated matches golden")
            or do {
                my $cand = $candidates[0] // '<no candidates>';
                my $head = substr($cand, 0, 400);
                diag("first candidate head: $head");
            };
    } else {
        is($actual, $expected,
            "$golden_name: schedule-generated matches golden");
    }
}

done_testing();
