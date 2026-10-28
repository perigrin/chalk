# ABOUTME: push through a reference while a read through a reference waits to
# ABOUTME: be made: the read may be of the same array -- refused, not misread.
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


# `my $g = scalar @{ $self->{s} }; push $self->{s}->@*, $t` counted after the
# push: "x1x2" for perl's "x0x1" (pvm 230). The count waits to be made where
# it is used; a push through the reference ran first.
for my $src (
    q{sub f { my ($self) = @_; my $g = scalar @{ $self->{s} }; push $self->{s}->@*, "t"; return "x$g" } my $o = { s => [] }; print f($o), f($o), "\n";},
    q{sub f { my ($self, $t) = @_; my $g = scalar @{ $self->{s} }; push $self->{s}->@*, $t; return "x$g" } my $o = { s => [] }; print f($o, "a"), f($o, "b"), "\n";},
) {
    my $got = eval { through_llvm($src) };
    my $err = $@;
    my $want = qx($^X -e '$src');
    ok(defined $got ? $got eq $want : $err =~ /GAP/, "perl's answer or refused: $src")
        or diag "got: ", $got // $err;
}

done_testing;
