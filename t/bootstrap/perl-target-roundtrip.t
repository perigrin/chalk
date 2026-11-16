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
    [ 'grouping parens around a // are kept before =~',
      "class RT2 {\n    sub f(\$v) { return ( \$v // '' ) =~ /\\A(?:a|b)\\z/ ? 1 : 0 }\n}\n",
      q{print join(',', map { RT2::f($_) } undef, 'a', 'ab'), "\n";} ],
    [ 'grouping parens are kept on both sides of a tighter operator',
      join('', "class RT2b {\n",
          "    sub mul(\$a, \$b, \$c) { return ( \$a + \$b ) * \$c }\n",
          "    sub sub3(\$a, \$b, \$c) { return \$a - ( \$b - \$c ) }\n",
          "    sub plain(\$a, \$b, \$c) { return \$a + \$b * \$c }\n",
          "    sub left(\$a, \$b, \$c) { return \$a - \$b - \$c }\n",
          "    sub pow(\$a, \$b, \$c) { return ( \$a ** \$b ) ** \$c }\n",
          "    sub notand(\$a, \$b) { return !( \$a && \$b ) ? 1 : 0 }\n",
          "    sub orand(\$a, \$b, \$c) { return ( \$a || \$b ) && \$c ? 1 : 0 }\n",
          "    sub cat(\$a) { return ( \$a ? 'y' : 'n' ) . '!' }\n",
          "}\n"),
      q{print join(',', RT2b::mul(1,2,3), RT2b::sub3(10,4,3), RT2b::plain(1,2,3), RT2b::left(10,4,3), RT2b::pow(2,3,2), RT2b::notand(1,0), RT2b::orand(1,0,0), RT2b::cat(0)), "\n";} ],
    [ 'a list operator needs parens only when something follows it',
      join('', "class RT2c {\n",
          "    sub last_arg(\@a) { return join('-', map { \$_ * 2 } \@a) }\n",
          "    sub mid_arg(\@a) { return join('-', ( map { \$_ * 2 } \@a ), 'e') }\n",
          "    sub or_die(\$x) { return \$x || die 'none' }\n",
          "}\n"),
      q{print RT2c::last_arg(1, 2), '|', RT2c::mid_arg(1, 2), '|', RT2c::or_die(3), "\n"; eval { RT2c::or_die(0) }; print $@;} ],
    [ 'a ternary with an empty-list arm keeps both arms',
      join('', "class RT3 {\n",
          "    sub g(\$v) { return \$v ? 'x' : () }\n",
          "    sub h(\$v) { return \$v ? () : 'y' }\n",
          "    sub e() { my \@a = (); return scalar(\@a) }\n",
          "}\n"),
      q{my @r = RT3::g(0); my @s = RT3::g(1); my @t = RT3::h(1); my @u = RT3::h(0); print scalar(@r), scalar(@s), scalar(@t), scalar(@u), RT3::e(), "\n";} ],
    [ 'a double-quoted string with escapes keeps its characters',
      join('', "class RT4 {\n",
          "    sub h() { return \"a\\nb\\t\\\"c\\\"\" }\n",
          "    sub d(\$x) {\n",
          "        if (\$x) {\n",
          "            die \"MOP: must be defined\\n\";\n",
          "        }\n",
          "        return 'ok';\n",
          "    }\n",
          "}\n"),
      q{my $h = RT4::h(); $h =~ s/([^ -~])/sprintf('<%02x>', ord $1)/ge; print $h, "|", RT4::d(0), "\n"; eval { RT4::d(1) }; print "[$@]\n";} ],
    [ 'the strings undef, true and false stay strings; the keywords stay keywords',
      join('', "class RT8 {\n",
          "    sub s() { return 'undef' }\n",
          "    sub st() { return 'true' . '/' . 'false' }\n",
          "    sub ku() { return defined(undef) ? 'def' : 'undef-kw' }\n",
          "    sub kt() { return true ? 'T' : 'F' }\n",
          "    sub kf() { return false ? 'T' : 'F' }\n",
          "}\n"),
      q{print join(',', RT8::s(), RT8::st(), RT8::ku(), RT8::kt(), RT8::kf()), "\n";} ],
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
