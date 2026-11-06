# ABOUTME: T2 slice 18 -- perl's class feature: new from named parameters and defaults, fields
# ABOUTME: read and written in methods, an array field, :reader, methods dispatched by the run-time MOP.
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
for my $case (
    [ q{use v5.42; use experimental 'class';
class Pt { field $x :param = 0; field $y :param :reader = 0; field @log;
  method move ($dx) { $x += $dx; push @log, $dx; return $self }
  method x { $x } method n { scalar @log } }
my $p = Pt->new(x => 1, y => 2); $p->move(3)->move(4); print $p->x, " ", $p->y, " ", $p->n, " ", ref($p), "\n";}, 'fields, params, a reader, an array field' ],
    [ q{use v5.42; use experimental 'class';
class C { field $n :param = 5; method get { $n } }
print C->new->get, C->new(n => 2)->get, "\n";}, 'a default, and a param over it' ],
    [ q{use v5.42; use experimental 'class';
class Ay { field $v :param; method v { $v } } class Be { field $v :param; method v { $v * 2 } }
sub show { my ($o) = @_; return $o->v } print show(Ay->new(v => 3)), show(Be->new(v => 3)), "\n";}, 'two classes, a method through a sub parameter' ],
    [ q{use v5.42; use experimental 'class';
class C { field $n :param = 1; field %h; ADJUST { $n = $n * 7; $h{a} = 1 } method n { $n } method k { join ",", keys %h } }
my $c = C->new(n => 2); print $c->n, $c->k, "\n";}, 'ADJUST after the fields, a hash field' ],
    [ q{use v5.42; use experimental 'class';
class Registry { field %classes; method add ($name) { $classes{$name} = 1; return $self } method classes { return values %classes } }
my $r = Registry->new->add("A")->add("B"); my @all = $r->classes; my $n = $r->classes; print scalar(@all), " $n\n";}, 'return values: the list, or its count (pvm 246)' ],
    [ q{use v5.42; use experimental 'class';
class R { field %h; method add ($n) { $h{$n} = 1 } method n { return scalar(keys %h) } } my $r = R->new; $r->add("A"); print $r->n, "\n";}, 'return scalar(keys %h) is a count in a list too' ],
    [ q{use v5.42; use experimental 'class';
class Pa { field $a :param = 1; field @s; ADJUST { push @s, "p" } method a { $a } method s { join "", @s } method who { "pa" } }
class Ch :isa(Pa) { field $b :param = 2; ADJUST { $b = $b + 1 } method b { $b } method who { "ch" } }
my $c = Ch->new(a => 5); print $c->a, $c->b, $c->s, $c->who, Pa->new->who, ref($c), "\n";}, ':isa: the parent first, its fields and ADJUST, an override' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# PERL DIES or T2 lacks it: perl's answer, or refused.
TODO: {
    local $TODO = 'Context.pm makes an object missing a required parameter (perl dies); T2 has no die yet';
    my $src = q{use v5.42; use experimental 'class'; class C { field $n :param; } my $c = eval { C->new } ; print defined $c ? "made" : "died", "\n";};
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "a required parameter missing: perl's answer");
}

done_testing;
