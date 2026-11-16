# ABOUTME: Round-trips small sources through Target::Perl and runs both under perl.
# ABOUTME: Each case's driver must print the same thing for the original and the emission.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Perl::Target::Perl;

my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'pipeline OK') or BAIL_OUT('pipeline');
my $generated = Chalk::Bootstrap::BNF::Target::Perl->new->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::RoundTripTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::RoundTripTest::grammar();

my $dir = tempdir(CLEANUP => 1);

sub emit($source) {
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    $parser->semiring->reset_cache;
    my $mop    = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $result = $parser->parse_value($source);
    return undef unless defined $result && !$result->is_zero && defined $mop;
    return Chalk::Bootstrap::Perl::Target::Perl->new->generate($mop)->{'main.pm'};
}

# Run $code (a module) then $driver under a fresh perl; stdout and stderr together.
sub run_perl($tag, $code, $driver) {
    my $file = "$dir/$tag.pm";
    open my $fh, '>:utf8', $file or die "$file: $!";
    print $fh $code, "\n1;\n";
    close $fh;
    open my $run, '-|', $^X, '-e',
        "open STDERR, '>&', \\*STDOUT; \$| = 1; require q{$file}; $driver"
        or die "run: $!";
    local $/;
    my $out = <$run> // '';
    close $run;
    # Where a message was raised differs between the two files; what it says must not.
    $out =~ s/ at \S+ line \d+\.?//g;
    return $out;
}

my $HEAD = "use 5.42.0;\nuse utf8;\nuse experimental 'class';\n";

# name, source (after $HEAD), driver (prints the observed behaviour)
my @cases = (
    [ 'a sub without a signature takes any arguments',
      "class RT1 {\n    sub identity_kind { 'hash_consed' }\n}\n",
      q{print RT1->identity_kind, "|", RT1::identity_kind(1, 2), "\n";} ],
    [ 'a sub with an empty signature takes no arguments',
      "class RT1b {\n    sub none() { 'n' }\n}\n",
      q{print RT1b::none(), "\n"; eval { RT1b::none(1) }; print $@;} ],
);

for my $case (@cases) {
    my ($name, $body, $driver) = $case->@*;
    state $n = 0;
    $n++;
    my $source = $HEAD . $body;
    my $code = emit($source);
    ok(defined $code, "$name: emits") or next;
    my $want = run_perl("orig$n", $source, $driver);
    my $got  = run_perl("emit$n", $code, $driver);
    is($got, $want, "$name: the emission behaves as the source")
        or diag("emitted:\n$code");
}

done_testing();
