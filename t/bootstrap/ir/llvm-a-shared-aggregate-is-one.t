# ABOUTME: A file-level array or hash a sub shares is one aggregate, read and written by
# ABOUTME: every graph through a module global -- B::SoN -> chalk -> lli == perl.
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

# A SHARED AGGREGATE IS ONE AGGREGATE. `my @p` at file level that a named
# sub reads or writes is the same @p in every graph (PadAccess shared), and
# was refused ("a store to a shared file lexical @p that is not a scalar",
# ~17 pvm cases across names). It lives behind a module global pointer,
# made empty on first use; assigning the whole aggregate overwrites it in
# place, so a reference taken before still names it.
for my $case (
    [ q{my @p = (1, 2); sub f { push @p, $_[0]; return scalar(@p) } my %h; sub g { $h{$_[0]} = 1; return scalar(keys %h) } print f(3), " @p ", g("b"), g("a"), g("b"), "\n";}, "3 1 2 3 122\n", 'an array and a hash, written by subs' ],
    [ q{my @p = (1); my $r = \@p; sub f { @p = (5, 6) } f(); print "@$r\n";}, "5 6\n", 'a whole assignment keeps a reference' ],
    [ q{my %c; sub put { $c{$_[0]} = $_[1] } sub get { $c{$_[0]} // "u" } put(a => 1); print get("a"), get("b"), "\n";}, "1u\n", 'a hash two subs share' ],
    [ q{sub f { my @p = (5); my $c = sub { push @p, $_[0] }; $c->(1); $c->(2); my $a = "@p"; @p = (); $c->(3); return "$a/@p" } print f(), "\n";}, "5 1 2/3\n", 'a read of the whole is taken where it stands (pvm)' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
