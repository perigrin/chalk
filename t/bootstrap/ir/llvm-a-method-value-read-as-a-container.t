# ABOUTME: An element of a method's value (`$phi->inputs->[0]`), and a store keyed by
# ABOUTME: one (pvm 175): a read an inlined method left waiting is its own.
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
    [ q{package N { sub new { bless { o => $_[1], i => $_[2] }, $_[0] } sub operation { $_[0]{o} } sub inputs { $_[0]{i} } }
sub f { my ($phi) = @_; my $init = $phi->inputs->[0]; if ($init->operation eq 'P') { my $vd = $init->inputs->[0]; return "vd=" . $vd->operation } "no" }
print f(N->new("Phi", [N->new("P", [N->new("V", [])])])), "\n";}, 'an element of an element of a method value' ],
    [ q{package N { sub new { bless { o => $_[1], i => $_[2] }, $_[0] } sub operation { $_[0]{o} } sub inputs { $_[0]{i} } }
my $s = {}; sub f { my ($self, $phi) = @_; my $init = $phi->inputs->[0]; $self->{t}{ $init->operation } = 1; } f($s, N->new("Phi", [N->new("P", [])])); print join(",", keys %{$s->{t}}), "\n";}, 'a store keyed by a method value' ],
    [ q{package N { sub new { bless { o => $_[1], i => $_[2], id => $_[3] }, $_[0] } sub operation { $_[0]{o} } sub inputs { $_[0]{i} } sub id { $_[0]{id} } }
sub upd { my ($self, $phi, $ref) = @_; my $inputs = $phi->inputs; return unless defined $inputs && @$inputs; my $init = $inputs->[0]; return unless defined $init;
  if ($init->operation eq 'PadAccess') { my $vd = $init->inputs->[0]; if (defined $vd && $vd->operation eq 'VarDecl') { $self->{t}{ $vd->id } = $ref; $self->{p}{ $phi->id } = $vd->id; return } } }
my $s = {}; upd($s, N->new("Phi", [N->new("PadAccess", [N->new("VarDecl", [], 5)])], 9), "R"); upd($s, N->new("Phi", [N->new("PadAccess", [undef])], 3), "Q"); upd($s, N->new("Phi", [], 4), "Z");
print join(",", map { "$_=$s->{t}{$_}" } sort keys %{$s->{t}}), " ", join(",", %{$s->{p}}), "\n";}, 'pvm 175' ],
    [ q{package N { sub new { bless { o => $_[1], i => $_[2] }, $_[0] } sub operation { $_[0]{o} } sub inputs { $_[0]{i} } }
sub upd { my ($self, $init) = @_; if ($init->operation eq "P") { my $vd = $init->inputs->[0]; if ($vd->operation eq "V") { $self->{t} = 1; return } } }
my $s = {}; upd($s, N->new("P", [N->new("V", [])])); print scalar(keys %$s), "\n";}, q{a bare return in a sub called for nothing} ],
    [ q{package N { sub new { bless { o => $_[1], i => $_[2] }, $_[0] } sub operation { $_[0]{o} } sub inputs { $_[0]{i} } }
sub upd { my ($self, $phi) = @_; my $inputs = $phi->inputs; return unless @$inputs; my $init = $inputs->[0]; if ($init->operation eq "P") { $self->{t} = 1; return } 0 }
my $s = {}; upd($s, N->new("Phi", [])); print scalar(keys %$s), "\n";}, q{a builtin read after an inlined method of the same node id} ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    # pvm 175 goes on to a join over a hash, and a bare return's List merge
    # has no machine layout: refused by name, not yet lowered.
    elsif ($name =~ /\A(?:pvm 175|a bare return)/) { like($@, qr/GAP/, "$name: refused by name") }
    else { fail("$name: perl's answer"); diag $@ }
}

done_testing;
