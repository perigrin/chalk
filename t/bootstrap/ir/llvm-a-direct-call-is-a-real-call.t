# ABOUTME: a direct call to a sub with scalar parameters is a real call to its define,
# ABOUTME: not an inlined copy of its body: through B::SoN -> chalk -> lli == perl.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

sub through_llvm ($src, $env) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    local @ENV{ keys %$env } = values %$env;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return ($out, $pl, $units->[0]{ll});
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    return scalar qx($^X $pl 2>/dev/null);
}




# perigrin, 2026-10-31: "inlining is/was a premature optimization". A direct
# call lowers to `call @main__NAME`, the body emitted once as a define.
for my $case (
    [ q{use v5.36; sub twice ($n) { return $n * 2 } print twice(3) + twice(4), "\n";}, 'twice', 'twice' ],
    [ q{use v5.36; sub greet ($who) { return "hi " . $who } print greet("a"), " ", greet("b"), "\n";}, 'a Str parameter and result', 'greet' ],
    [ q{use v5.36; sub add ($x, $y) { return $x + $y } print add(2, 3), "\n";}, 'two parameters', 'add' ],
    [ q{use v5.36; sub ev ($n) { $n == 0 ? 1 : od($n - 1) } sub od ($n) { $n == 0 ? 0 : ev($n - 1) } print ev(4), ev(3), "\n";}, 'two subs calling each other', 'ev' ],
) {
    my ($src, $name, $sub) = @$case;
    my ($got, $pl, $ll) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($ll // '', qr/^define [^\n]*\@main__$sub\(/m, "$name: $sub is a define");
    like($ll // '', qr/= call [^\n]*\@main__$sub\(/, "$name: and is called");
}

# A sub that reads @_ the plain ways -- a list assign from it, leading
# shifts, or $_[N] -- is called through its define too: B::SoN's graph
# connects each read to its argument (ArgsSource).
for my $case (
    [ q{sub add { my ($x, $y) = @_; return $x + $y } print add(2, 3), " ", add(4, 5), "\n";}, 'a list assign from @_', 'add' ],
    [ q{sub add { my $x = shift; my $y = shift; return $x + $y } print add(2, 3), "\n";}, 'two shifts', 'add' ],
    [ q{sub add { return $_[0] + $_[1] } print add(2, 3), "\n";}, '$_[N] reads', 'add' ],
    [ q{sub hi { my ($who) = @_; return "hi " . $who } print hi("a"), "\n";}, 'a Str argument', 'hi' ],
) {
    my ($src, $name, $sub) = @$case;
    my ($got, $pl, $ll) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($ll // '', qr/^define [^\n]*\@main__$sub\(/m, "$name: $sub is a define");
    like($ll // '', qr/= call [^\n]*\@main__$sub\(/, "$name: and is called");
}

# A sub with an optional parameter: a call may pass fewer arguments than its
# define takes. Perl's answer either way (pvm 030 took a refusal here).
for my $case (
    [ q{use v5.36; sub add_up ($a, $b = 3) { $a + $b } print add_up(1), " ", add_up(1, 10), "\n";}, 'pvm 030: a default' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

done_testing;
