# ABOUTME: Bare returns in nested arms, merged arm by arm into the list a sub returns: each
# ABOUTME: merge a way into that list, an array, each way's value a list of it.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

my @same = (
    [ q{package N { sub new { bless { o => $_[1], i => $_[2], id => $_[3] }, $_[0] } sub operation { $_[0]{o} } sub inputs { $_[0]{i} } sub id { $_[0]{id} } } sub upd { my ($self, $phi, $ref) = @_; my $inputs = $phi->inputs; return unless defined $inputs && @$inputs; my $init = $inputs->[0]; return unless defined $init; if ($init->operation eq 'PadAccess') { my $vd = $init->inputs->[0]; if (defined $vd && $vd->operation eq 'VarDecl') { $self->{t}{ $vd->id } = $ref; $self->{p}{ $phi->id } = $vd->id; return } } } my $s = {}; upd($s, N->new("Phi", [N->new("PadAccess", [N->new("VarDecl", [], 5)])], 9), "R"); upd($s, N->new("Phi", [N->new("PadAccess", [undef])], 3), "Q"); upd($s, N->new("Phi", [], 4), "Z"); print join(",", map { "$_=$s->{t}{$_}" } sort keys %{$s->{t}}), " ", join(",", %{$s->{p}}), "\n";},
      'nested bare returns, called in void context' ],
    [ q{my %t; sub f { my ($k) = @_; return unless $k; if ($k > 1) { $t{$k} = 1; return } } my @l = f(2); my @m = f(1); my $s = f(0); print scalar(@l), scalar(@m), defined $s ? "d" : "u", " ", join(",", keys %t), "\n";},
      'nested bare returns, called in list and scalar context' ],
);

for my $case (@same) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

done_testing;
