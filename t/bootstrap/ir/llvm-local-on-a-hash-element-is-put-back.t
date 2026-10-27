# ABOUTME: `local $h{k} = v` is seen by what runs in its scope and put back where it ends
# ABOUTME: (deleted if the key was not there): B::SoN -> chalk -> lli == perl.
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

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
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
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# B::SoN reads the element before the local store (and whether it exists)
# and puts it back at the scope's end (ElemRestore); chalk lowered neither.
for my $c (
    [ q{my %h = (a => 1); sub f { local $h{a} = 2; $h{a} } print f(), $h{a}, "\n";} ],
    [ q{my %h = (a => 1); sub f { local $h{b} = 2; join ",", sort keys %h } print f(), "|", join(",", sort keys %h), "\n";} ],
    [ q{my %h = (a => 1); sub g { $h{a} } sub f { local $h{a} = 5; g() } print f(), g(), "\n";} ],
    [ q{my $r = { a => 1 }; sub f { my ($s) = @_; local $s->{a} = 2; $s->{a} } print f($r), $r->{a}, "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
