# ABOUTME: a qr// value keeps its flags: a match through it uses them, and it prints as
# ABOUTME: perl stringifies it, (?^FLAGS:pattern): B::SoN -> chalk -> lli == perl.
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


# A qr// printed was refused (pvm 389).
for my $c (
    [ q{my $r = qr/abc/; print "$r\n";} ],
    [ q{my $r = qr/a.c/m; print "$r\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# THE LOADER DROPPED A qr//'s FLAGS: `"a" =~ qr/A/i` matched case-sensitive
# (0 for perl's 1). Perl's answer, or refused.
for my $src (q{my $r = qr/A/i; my $x = "a" =~ $r ? 1 : 0; print "$x\n";},
             # ...and split's pattern: `split /x/i` split by "x" alone (2 for 3)
             q{my @f = split /x/i, "aXbxc"; print scalar(@f), "\n";}) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    ok(( defined $got && $got eq $want ) || $@ =~ /GAP/, "perl's answer or refused: $src")
        or diag "got: " . ( $got // "undef" ) . " $@";
}

done_testing;
