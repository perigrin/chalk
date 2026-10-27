# ABOUTME: a direct call of a sub no one defines runs its package's AUTOLOAD, with
# ABOUTME: $AUTOLOAD set to the full name: B::SoN -> chalk -> lli == perl, or refused.
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


# The loader found no sub by the name and refused the call (pvm 409, 011).
for my $c (
    [ q{our $AUTOLOAD; sub AUTOLOAD { my $n = $AUTOLOAD; $n =~ s/.*:://; return "auto:$n" } print missing(), "\n";} ],
    [ q{our $AUTOLOAD; sub AUTOLOAD { return $AUTOLOAD . "=" . $_[0] } print one(1), " ", two(2), "\n";} ],
    # A sub that IS defined runs itself, not AUTOLOAD.
    [ q{our $AUTOLOAD; sub AUTOLOAD { "auto" } sub here { "here" } print here(), " ", gone(), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# $AUTOLOAD READ OUTSIDE AUTOLOAD: B::SoN does not order that read after the
# call (the call is not in memory), so it read the name before it was stored.
{
    my $src = q{our $AUTOLOAD; sub AUTOLOAD { "a" } print x(), " $AUTOLOAD\n";};
    my $got = eval { through_llvm($src) };
    ok(( defined $got && $got eq "a main::x\n" ) || $@ =~ /GAP/, "\$AUTOLOAD read after the call: perl's answer or refused")
        or diag "got: " . ( $got // "undef" ) . " $@";
}

# A STRING EVAL MAY DEFINE THE SUB at run time, and then perl calls it, not
# AUTOLOAD: refused, never answered with AUTOLOAD's value.
{
    my $src = q{eval q{sub zed { 42 }}; sub AUTOLOAD { "auto" } print zed(), "\n";};
    my $got = eval { through_llvm($src) };
    ok(( defined $got && $got eq "42\n" ) || $@ =~ /GAP/, "a sub a string eval may define: perl's answer or refused")
        or diag "got: " . ( $got // "undef" ) . " $@";
}

done_testing;
