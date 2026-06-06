# ABOUTME: One-shot script to regenerate the three codegen golden files affected by the E1 fix.
# ABOUTME: Runs Target::Perl on each source file and writes the updated golden to t/fixtures/codegen-goldens/.
use 5.42.0;
use utf8;
use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Perl::Target::Perl;

my $raw_ir = perl_pipeline();
die "pipeline failed" unless defined $raw_ir;
my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::GoldenRegen/g;
eval $generated;
die "eval failed: $@" if $@;
my $gen_grammar = Chalk::Grammar::Perl::GoldenRegen::grammar();

my @files = (
    'lib/Chalk/IR/Node/Constant.pm',
    'lib/Chalk/IR/Node/Return.pm',
    'lib/Chalk/IR/Node/Start.pm',
);

for my $src (@files) {
    open my $fh, '<:utf8', $src or die "cannot open $src: $!";
    local $/;
    my $source = <$fh>;
    close $fh;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $result = $parser->parse_value($source);
    if (!defined $result || $result->is_zero()) {
        warn "ZERO parse result for $src\n";
        next;
    }
    if (!defined $mop) {
        warn "UNDEF MOP for $src\n";
        next;
    }

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
    my $out = $target->generate($mop);
    if (!defined $out) {
        warn "UNDEF output for $src\n";
        next;
    }
    my $text = ref($out) eq 'HASH' ? (values $out->%*)[0] : $out;

    # Derive golden filename: lib/Chalk/IR/Node/Constant.pm -> Chalk__IR__Node__Constant.pl.golden
    my $golden_name = $src;
    $golden_name =~ s{^lib/}{};
    $golden_name =~ s{\.pm$}{};
    $golden_name =~ s{/}{__}g;
    $golden_name .= '.pl.golden';

    my $golden_path = "t/fixtures/codegen-goldens/$golden_name";
    open my $gfh, '>:utf8', $golden_path or die "cannot write $golden_path: $!";
    print $gfh $text;
    close $gfh;
    print "Updated: $golden_path\n";
}
