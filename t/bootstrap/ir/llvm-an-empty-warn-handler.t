# ABOUTME: warn under an empty $SIG{__WARN__} handler writes nothing and is
# ABOUTME: true; warn with no handler, or another handler, is refused by name.
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


# An empty __WARN__ handler swallows each warning; warn yields 1 (pvm 027).
for my $src (
    q{local $SIG{__WARN__} = sub { }; my @g = (warn "a", "b"); my @c = (warn("a"), "b"); print scalar @g, scalar @c, "\n";},
    q{$SIG{__WARN__} = sub { }; warn "x\n"; print "ok ", warn("y"), "\n";},
) {
    my $want = qx($^X -e '$src' 2>&1);
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# perl's own message names the file and line, which this run does not
# share; a handler that does something runs code this does not call.
for my $src (
    q{warn "x\n"; print "ok\n";},
    q{$SIG{__WARN__} = sub { print "got @_" }; warn "x\n";},
    q{$SIG{__DIE__} = sub { }; print "ok\n";},
) {
    my $got = eval { through_llvm($src) };
    like($@, qr/GAP/, "refused by name: $src") or diag "got: ", $got // '';
}

done_testing;
