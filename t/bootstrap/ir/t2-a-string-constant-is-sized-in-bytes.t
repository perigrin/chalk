# ABOUTME: A string constant past ASCII is declared the size it is printed: one byte a character
# ABOUTME: up to 0xFF (the wire hands them upgraded); a wider character is refused by name, never mis-sized.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

sub t2 ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh; print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = ( $units // [] )->[0] // {};
    return ( !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef, $err // $u->{path_why} // $u->{err}, $pl );
}

# Chalk::MOP::Class's own die message holds an em dash: B::SoN hands its
# UTF-8 bytes over as characters below 0x100, and `use bytes` counted each
# twice -- an lli type error.
{
    my ($ll, $why, $pl) = t2(qq{my \$s = "caf\\xe9 \\xe2\\x80\\x94\\n"; print \$s;\n});
    ok(defined $ll, 'characters up to 0xFF: lowered through T2') or diag $why;
    if (defined $ll) {
        my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $lf, ':utf8'; print $lf $ll; close $lf;
        my $got  = qx(timeout 20 $LLI $llp 2>&1);
        my $want = qx($^X $pl 2>&1);
        is($got, $want, '... perl\'s bytes and length');
    }
}

# A CHARACTER PAST 0xFF has no one byte: refused by name, not mis-sized.
{
    my ($ll, $why) = t2(qq{use utf8; no warnings; my \$s = "\\x{263a}\\n"; print \$s;\n});
    ok(!defined $ll, 'a character past 0xFF: not lowered');
    like($why // '', qr/a string constant with a character past 0xFF/, '... refused by name');
}

done_testing;
