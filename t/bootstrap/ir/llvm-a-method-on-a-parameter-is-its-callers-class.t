# ABOUTME: A method called on a sub's parameter dispatches on the class the call site passed:
# ABOUTME: inlined there, its object's class is static: B::SoN -> chalk -> lli == perl.
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

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
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
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# `sub f { my ($n) = @_; $n->val }` names no class -- nothing in f says
# which -- and was refused ("Call(method) 'val' has no class_name", pvm
# 212). Inlined at `f(N->new(5))`, $n IS that object, of class N.
for my $case (
    [ q{package N { sub new { bless { v => $_[1] }, $_[0] } sub val { $_[0]{v} } } sub f { my ($n) = @_; my $v = $n->val; return "v=$v" } print f(N->new(5)), "\n";}, "v=5\n", 'a constructor passed in' ],
    [ q{package A { sub new { bless {}, $_[0] } sub who { "a" } } package B { sub new { bless {}, $_[0] } sub who { "b" } } sub f { my ($o) = @_; return $o->who } print f(A->new), f(B->new), "\n";}, "ab\n", 'two call sites, two classes' ],
    [ q{package A { sub who { "lit" } } sub f { $_[0]->who } print f(bless {}, "A"), "\n";}, "lit\n", 'a literal bless passed in' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A REFERENCE PASSED WHERE THE SUB READS A SCALAR (its other callers pass
# undef) is boxed, tag and all; it was refused as a coercion that "would not
# keep the value" (pvm 204).
{
    my $got = eval { through_llvm(q{sub show { my ($r) = @_; return defined $r ? ref($r) : "n" } my $h = {}; print show($h), show(undef), "\n";}) };
    is($got, "HASHn\n", 'a reference into a Scalar parameter') or diag $@;
}

# AN OBJECT WHOSE CLASS IS NOT STATIC -- read back out of a container --
# is dispatched by the class its bless names (run-time dispatch).
{
    my $got = eval { through_llvm(q{package A { sub new { bless {}, $_[0] } sub who { "a" } } my @o = (A->new); sub f { $_[0]->who } print f($o[0]), "\n";}) };
    is($got, "a\n", 'an object out of a container: perl\'s answer') or diag $@;
}

done_testing;
