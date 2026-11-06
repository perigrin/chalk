# ABOUTME: T2 slice 6 -- a blessed {...} is an object: bless, ref, and a method call
# ABOUTME: resolved to its class, checked at run time against the object's class.
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
    [ q{package N { sub new { bless { v => $_[1] }, $_[0] } sub val { $_[0]{v} } }
my $n = N->new(5); print $n->val, " ", ref($n), "\n";}, 'new, an accessor, ref of an object' ],
    [ q{my $h = {a => 1}; print ref($h), "|", ref(5), "|\n";}, 'ref of a hash reference and of a number' ],
    [ q{package Q { sub new { my $class = shift; my $v = shift; return bless { v => $v }, $class }
  sub get { my $self = shift; return $self->{v} } sub twice { my ($self, $k) = @_; return $self->get * 2 + $k } }
my $q = Q->new(4); print $q->twice(1), " ", $q->get, "\n";}, 'shift-style methods, a method calling a method' ],
    [ q{package A { sub new { bless {}, shift } sub hi { "a" } }
package B { sub new { bless {}, shift } sub hi { "b" } }
print A->new->hi, B->new->hi, "\n";}, 'two classes, each its own method' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# AN OBJECT OF ANOTHER CLASS THAN THE ONE THE CALL WAS RESOLVED TO: perl's
# answer, or refused by name -- never another method's answer.
for my $case (
    [ q{package A { sub new { bless {}, shift } sub hi { "a" } }
package B { sub new { bless {}, shift } sub hi { "b" } }
sub pick { $_[0] ? A->new : B->new } print pick(1)->hi, pick(0)->hi, "\n";}, 'a sub returning either class' ],
    [ q{package P { sub new { bless {}, shift } sub hi { "p" } sub call_hi { $_[0]->hi } }
package K { our @ISA = ('P'); sub hi { "k" } }
print P->new->call_hi, K->new->call_hi, "\n";}, 'a subclass overriding the method its parent calls' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    else { like($@, qr/GAP|refused at run time|^lower: /, "$name: refused by name") }
}

done_testing;
