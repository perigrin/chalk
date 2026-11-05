# ABOUTME: A read through a reference, made before a call that stores through it
# ABOUTME: (pvm 233), is made before the call: it is perl's, at that version.
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
    [ q{my %v = (a => {n => "x"}, b => {n => "y"}); sub vars { \%v } sub emit { my $h = $_[0]; $h->{n} = "z"; $_[1] }
sub f { my @l; for my $k (sort keys vars()->%*) { my $info = vars()->{$k}; my $s = $info->{n}; my $e = emit($info, $k eq "a" ? 1 : undef); push @l, "$s=$e" if defined $e } "@l" }
print f(), "\n";}, 'pvm 233' ],
    [ q{my %v = (a => {n => "x"}, b => {n => "y"}); sub emit { my $h = $_[0]; $h->{n} = "z"; $_[1] }
my @l; for my $k (sort keys %v) { my $info = $v{$k}; my $s = $info->{n}; my $e = emit($info, $k eq "a" ? 1 : 2); push @l, "$s=$e" } print "@l $v{a}{n}\n";}, 'pvm 233 shape: the read before, the store in the call' ],
    [ q{my %v = (a => {n => "x"}, b => {n => "y"}); sub emit { my $h = $_[0]; $h->{n} = "z"; $_[1] }
my @l; for my $k (sort keys %v) { my $info = $v{$k}; my $e = emit($info, $k eq "a" ? 1 : 2); my $s = $info->{n}; push @l, "$s=$e" } print "@l\n";}, 'a read after the call sees its store' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    elsif ($name =~ /\Apvm/) { fail("$name: perl's answer"); diag $@ }
    else { like($@, qr/GAP/, "$name: refused by name") }
}

done_testing;
