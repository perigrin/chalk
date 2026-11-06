# ABOUTME: T2 slice 7 -- a method call on a value of no static class is dispatched at run
# ABOUTME: time by the invocant's class, over the classes that define the method.
our $LAST_LL;
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
    $LAST_LL = $units->[0]{ll};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    local @ENV{ keys %$env } = values %$env;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return ($out, $pl);
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    return scalar qx($^X $pl 2>/dev/null);
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}
# TAKEN BY T2: perl's answer, through T2.
for my $case (
    [ q{package A { sub new { bless { v => $_[1] }, $_[0] } sub val { "a" . $_[0]{v} } }
package B { sub new { bless { v => $_[1] }, $_[0] } sub val { "b" . $_[0]{v} } }
sub f { my ($n) = @_; return $n->val }
print f(A->new(1)), f(B->new(2)), "\n";}, 'an object passed to a sub: each class its method' ],
    [ q{package N { sub new { my ($c, $v) = @_; bless { v => $v }, $c } sub add { my ($s, $x) = @_; return $s->{v} + $x } }
sub g { my ($o, $k) = @_; return $o->add($k) * 2 }
print g(N->new(3), 4), "\n";}, 'a method with an argument, through a parameter' ],
    [ q{package N { sub new { bless {}, $_[0] } sub hi { "n" } }
sub mk { my ($cls) = @_; return $cls->new } print ref(mk("N")), mk("N")->hi, "\n";}, 'a class name in a variable' ],
    [ q{package P { sub new { bless {}, shift } sub hi { "p" } sub call_hi { $_[0]->hi } }
package K { use parent -norequire, 'P'; sub hi { "k" } }
package L { use parent -norequire, 'P'; }
print P->new->call_hi, K->new->call_hi, L->new->call_hi, "\n";}, 'use parent: an override, an inherited method' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# PERL'S ANSWER, OR REFUSED BY NAME: inheritance, AUTOLOAD, a method no class has.
for my $case (
    [ q{package P { sub new { bless {}, shift } sub hi { "p" } }
package K { use parent -norequire, 'P'; }
sub f { $_[0]->hi } print f(K->new), f(P->new), "\n";}, 'an inherited method' ],
    [ q{package P { sub new { bless {}, shift } sub hi { "p" } }
package K { our @ISA = ('P'); }
sub f { $_[0]->hi } print f(K->new), f(P->new), "\n";}, 'an inherited method, @ISA' ],
    [ q{package P { sub new { bless {}, shift } our $AUTOLOAD; sub AUTOLOAD { "auto" } sub DESTROY {} }
sub f { $_[0]->hi } print f(P->new), "\n";}, 'AUTOLOAD' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    else { like($@, qr/GAP|refused at run time|^lower: /, "$name: refused by name") }
}

done_testing;
