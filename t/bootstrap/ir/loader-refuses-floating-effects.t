# ABOUTME: the loader refuses a wire whose write, call or bless is on no control chain (T2 would
# ABOUTME: never make it), and still loads the floating records it may; what B::SoN places, runs.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

require Chalk::CodeGen::Harness::Producer;
require Chalk::IR::Serialize::JSON;
require JSON::PP;


# floated($src, $is) -> why the loader refuses $src's wire once the node $is
# accepts is taken off the control chain (what followed it now follows what
# it followed), or '' where it loads. B::SoN places these nodes since its
# `placement`; the check is for a wire that does not.
sub floated ( $src, $is ) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    my $wire  = JSON::PP->new->utf8->decode( scalar qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null) );
    my $nodes = $wire->{methods}{'main::__PROGRAM__'}{nodes};
    my ($n) = grep { defined $_->{control_in} && $is->($_) } $nodes->@* or return 'no such node on the control chain';
    my $before = delete $n->{control_in};
    for my $m ( $nodes->@* ) {
        $m->{control_in} = $before if defined $m->{control_in} && $m->{control_in} == $n->{id};
        $m->{inputs} = [ map { defined $_ && !ref $_ && $_ == $n->{id} ? $before : $_ } $m->{inputs}->@* ] if $m->{op} =~ /\A(?:Region|If|Loop)\z/;
    }
    eval { Chalk::IR::Serialize::JSON::from_json( JSON::PP->new->utf8->canonical->encode($wire) ) };
    return $@ // '';
}
my $list_assign = sub ($n) { $n->{op} eq 'Assign' && defined $n->{fields}{targets} };
my $bless       = sub ($n) { $n->{op} eq 'Call' && ( $n->{fields}{name} // '' ) eq 'bless' };

# OFF THE CHAIN, each is refused by name: T2 would never make it. Each is a
# memory version (mem_out) with no control_in: the loader's invariant (L2)
# refuses it before any check of what chalk can lower (wire v2 stage 6).
my $OFF = qr/\AGAP: wire invariant L2: main::__PROGRAM__: \w+#\d+ is a memory version with no control_in/;
for my $case (
    [ q{my @a=(0); my $c; ($a[0], $c) = (5,6); print "$a[0] $c\n";},             $list_assign, $OFF, 'an element and a scalar' ],
    [ q{my %h; my $c; ($h{k}, $c) = (9, 10); print "$h{k} $c\n";},               $list_assign, $OFF, 'a hash element and a scalar' ],
    [ q{my $x = 1; my $g = sub { $x }; ($x) = (7); print $g->(), "\n";},          $list_assign, $OFF, 'a captured variable' ],
    [ q{my %h; @h{qw(a b)} = (1,2); print "$h{a} $h{b}\n";},                     $list_assign, $OFF, 'a hash slice' ],
    [ q{my @a = (0,0,0); @a[0,1] = (5,6); print "@a\n";},                        $list_assign, $OFF, 'an array slice' ],
    [ q{my $r = [0,0]; ($r->[0], $r->[1]) = (3,4); print "@$r\n";},              $list_assign, $OFF, 'elements through a reference' ],
    [ q{our @g = (0,0); ($g[0], $g[1]) = (3,4); print "@g\n";},                  $list_assign, $OFF, "a package array's elements" ],
    [ q{package K; sub hi { "hi" } package main; my $h = {}; my $o = bless $h, "K"; print $h->hi, "\n";}, $bless, $OFF, 'a bless of a variable read beside it' ],
) {
    my ( $src, $is, $name, $what ) = @$case;
    like( floated( $src, $is ), $name, "$what, off the chain: refused by name" );
}

# Each: [source, the refusal's name (undef: perl's output), what it is].
for my $case (
    # A list assignment to a place in memory, where B::SoN places it:
    [ q{my @a=(0); my $c; ($a[0], $c) = (5,6); print "$a[0] $c\n";},             undef, 'an element and a scalar' ],
    [ q{my $x = 1; my $g = sub { $x }; ($x, my $y) = (7, 8); print $g->(), " $y\n";}, undef, 'a captured variable and a fresh one' ],
    [ q{my @a = (1,2); ($a[0], $a[1]) = ($a[1], $a[0]); print "@a\n";},          undef, 'a swap of elements' ],
    [ q{my @a = (1,2,3); my $x = $a[0] + $a[1]; ($a[0], $a[1]) = (10, 20) if @ARGV; $a[2] = $x; print "@a\n";},
        undef, 'elements, in an arm not taken' ],
    # (placed: @_ assigned whole is the sub's own new elements, the caller's
    # $x untouched -- lowered since B::SoN's places-everywhere, audit 3 N2)
    [ q{sub f { @_ = (9, 9); $_[0] = 3 } my $x = 1; f($x); print "$x\n";},        undef, 'the arguments' ],
    # A call by a name made at run time: where B::SoN pins it (its
    # `placement-pins`), perl's output; floating, refused.
    [ q{package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; return } package main; my $o = C->new; my $m = "inc"; $o->$m(); print $o->{n}, "\n";},
        undef, 'a dynamic method call, its value unused' ],
    [ q{package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; return 5 } package main; my $o = C->new; my $m = "inc"; my $r = $o->$m(); print "$r $o->{n}\n";},
        undef, 'a dynamic method call that writes, its value used' ],
    # A bless, on the chain now: a ref() beside it reads at the bless's version.
    [ q{my $h = {}; my $o = bless $h, "K"; print ref($h), " ", ref($o), "\n";},  undef, 'a bless of a variable, ref() read beside it' ],
    [ q{package K; sub hi { "hi" } package main; my $h = {}; my $o = bless $h, "K"; print $h->hi, "\n";}, undef, 'a bless of a variable a method is then called on' ],
    # What may float:
    [ q{my ($p, $q) = (1, 2); ($p, $q) = ($q, $p); print "$p $q\n";},            undef, 'a list assignment of scalars is a record' ],
    [ q{sub f { my ($p, @r) = @_; return "$p @r" } print f(1, 2, 3), "\n";},      undef, 'the arguments, bound to fresh variables' ],
    [ q{our ($p, $q) = (1, 2); { local ($p, $q) = ($q, $p); print "$p$q" } print "$p$q\n";}, undef, 'package scalars, each stored on the chain' ],
    [ q{package Foo; sub hi { return "hi" } package main; my $o = bless {}, "Foo"; my $m = "hi"; print $o->$m, "\n";},
        undef, 'a dynamic call of a method that reads and writes nothing' ],
    [ q{package Foo; sub new { return bless { n => 3 }, shift } package main; my $o = Foo->new; print ref($o), " $o->{n}\n";},
        undef, 'a bless of a fresh hash, returned' ],
    [ q{package Foo; sub add { return $_[1] + $_[2] } package main; my $o = bless {}, "Foo"; my $m = "add"; print $o->$m(2, 3), "\n";},
        undef, 'a dynamic call printed where it stands' ],
    [ q{package C; sub v { ${$_[0]} } package main; my $x = 5; my $o = bless \$x, "C"; print ref($o), " ", $o->v, "\n";}, undef, 'a bless of a fresh scalar reference' ],
    [ q{package T; sub wrap { bless $_[1], $_[0] } package main; my $o = T->wrap({ n => 4 }); print ref($o), " $o->{n}\n";}, undef, 'a bless of an argument, returned' ],
    [ q{my $slot = 0; sub slot :lvalue { $slot } slot() = 42; print slot(), "\n";}, undef, 'an lvalue call, the place of a store on the chain' ],
) {
    my ( $src, $name, $what ) = @$case;
    my ( $v, $why ) = verdict($src)->@*;
    if ($name) { is( $v, 'REFUSED', "$what: refused" ) or diag "$v $why"; like( $why, $name, "$what: by name" ) }
    else       { is( $v, 'SAME', "$what: perl's output" ) or diag "$v $why" }
}

done_testing;
