# ABOUTME: The probe harness judges a program by what it printed AND how it ended: an lli
# ABOUTME: that prints perl's stdout but exits with another status is WRONG, never SAME.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempdir);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# Audit 2026-11-22, risk 11: the harness compared stdout and whether the
# program succeeded, so a program that died (perl's 255) and one that exited
# 1, or crashed, were the same verdict. lli here is a stand-in that prints
# what perl prints and exits as it is told: only the status differs.
my $dir = tempdir( CLEANUP => 1 );
sub fake_lli ($status) {
    my $f = "$dir/lli-$status";
    open my $o, '>', $f or die $!;
    print $o "#!/bin/sh\nprintf 'a\\n'\nexit $status\n";
    close $o;
    chmod 0755, $f;
    return $f;
}
my $pl = "$dir/p.pl";
{ open my $o, '>', $pl or die $!; print $o qq{print "a\\n"; die "x\\n";\n}; close $o }

# (AuditProbe takes its lli when it is loaded: each verdict in its own perl)
sub verdict ($lli) {
    my $out = qx(LLI=$lli $^X -Ilib -It/lib -MChalk::CodeGen::Harness::AuditProbe=run_probe -e 'print join "\\t", run_probe(shift)->\@*' $pl);
    return [ split /\t/, $out, 2 ];
}

my ( $v, $why ) = verdict( fake_lli(255) )->@*;
is( $v, 'SAME', 'perl died (255), the program died (255): SAME' ) or diag $why;
( $v, $why ) = verdict( fake_lli(1) )->@*;
is( $v, 'WRONG', 'perl died (255), the program exited 1 with the same stdout: WRONG' ) or diag $why;
like( $why // '', qr/exit/, 'and it says the exit status differs' );

done_testing;
