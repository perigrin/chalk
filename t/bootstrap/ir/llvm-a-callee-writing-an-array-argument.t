# ABOUTME: g(@a) where g writes $_[N] (pvm 199): @_ aliases the elements, so the
# ABOUTME: write reaches @a -- an element past its end does not.
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
    [ q{sub g { $_[0] = 9; scalar @_ } sub f { my ($x) = @_; my $n = g(@$x); "$n|@$x" } print f([1, 2, 3]), "\n";}, 'through a reference' ],
    [ q{sub g { $_[1] = "b"; scalar @_ } sub f { my @a = ("x", "y"); my $n = g(@a); "$n|@a" } print f(), "\n";}, 'a named array' ],
    [ q{sub g { $_[2] = 7; scalar @_ } sub f { my ($x) = @_; my $n = g(@$x); "$n|@$x|" . scalar(@$x) } print f([1]), "\n";}, 'past the end: @a keeps its length' ],
    [ q{sub g { $_[0] = 9; scalar @_ } sub ok1 { $_ > 1 }
sub f { my ($x, $c) = @_; my $s = "";
  for my $e ($c ? @$x : ()) { $s .= $e }
  my $k = join ",", grep { ok1() } ($c ? @$x : ());
  my $n = g($c ? @$x : ());
  return "$s|$k|$n|@$x" }
print f([1, 2, 3], 1), " ", f([4], 0), "\n";}, 'pvm 199' ],
    [ q{sub g { $_[0] = 9; scalar @_ } sub ok1 { $_ > 1 } sub f { my ($x, $c) = @_; my $s = ""; for my $e ($c ? @$x : ()) { $s .= $e } my $k = join ",", grep { ok1() } ($c ? @$x : ()); my $n = g(@$x); "$s|$k|$n|@$x" } print f([1, 2, 3], 1), " ", f([4], 0), "\n";}, q{a sub called twice: what the first call built is not left in the graph} ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    else { fail("$name: perl's answer"); diag $@ }
}

done_testing;
