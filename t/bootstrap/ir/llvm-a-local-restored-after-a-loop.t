# ABOUTME: A value read after a loop, before a `local` is put back at the end of
# ABOUTME: its scope, is the loop's value, not the restored one.
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
    [ q{our $x = 0; sub f { local $x = 0; $x += $_ for 1, 2; return $x } print f(), " $x\n";}, 'local $x' ],
    [ q{our %o = (bind => 0); sub f { local $o{bind} = 0; $o{bind} += $_ for 1, 2; return $o{bind} } print f(), " $o{bind}\n";}, 'local $o{k}' ],
    [ q{my $o = { bind => 0 }; sub f { local $o->{bind} = 0; $o->{bind} += $_ for 1, 2; return $o->{bind} } print f(), " $o->{bind}\n";}, 'local $o->{k}' ],
    [ q{my $o = { bind => undef }; sub f { local $o->{bind} = {}; $o->{bind}{$_} = 1 for qw(a b); return scalar keys $o->{bind}->%* } print f(), "\n";}, 'local $o->{k}, a hash filled in a loop' ],
    [ q{our $x = 0; sub f { local $x = 0; if ($ENV{N} // 1) { $x = 5 } return $x } print f(), " $x\n";}, 'local $x, set in an if' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    else { like($@, qr/GAP/, "$name: refused by name") }
}

done_testing;
