# ABOUTME: A method on an object a loop carries (`$c = $c->prev`, pvm 204): the call,
# ABOUTME: its class known only at run time, is a Scalar when every candidate returns one.
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
    [ q{package N { sub new { bless { id => $_[1], prev => $_[2] }, $_[0] } sub prev { $_[0]{prev} } sub id { $_[0]{id} } }
sub f { my ($ret) = @_; my @chain; my %seen; my @seeds = grep { defined } ($ret->prev);
  for my $ctrl (@seeds) { while (defined $ctrl) { last if $seen{ $ctrl->id }++; push @chain, $ctrl->id; $ctrl = $ctrl->prev } }
  return "@chain|" . scalar(@seeds) }
print f(N->new(0, N->new(1, N->new(2, N->new(3))))), "\n";}, 'pvm 204' ],
    [ q{package N { sub new { bless { id => $_[1], nx => $_[2] }, $_[0] } sub nx { $_[0]{nx} } sub id { $_[0]{id} } }
my $c = N->new(1, N->new(2, N->new(3))); my @ids; while (defined $c) { push @ids, $c->id; $c = $c->nx } print "@ids\n";}, 'pvm 204 shape: a linked walk' ],
    [ q{package N { sub new { bless { id => $_[1] }, $_[0] } sub id { $_[0]{id} } }
my @ids; for my $c (N->new(1), N->new(2)) { push @ids, $c->id } print "@ids\n";}, q{pvm 204 shape: "@a" after a run-time dispatch: no candidate writes $"} ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    else { fail("$name: perl's answer"); diag $@ }
}

done_testing;
