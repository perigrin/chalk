# ABOUTME: can() through T2 finds a followed module's sub nothing else calls: the
# ABOUTME: name it asks for reaches that sub, so the sub is loaded, not pruned.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile tempdir);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

my $lib = tempdir( CLEANUP => 1 );
{ open my $fh, '>', "$lib/R.pm" or die $!; print $fh "package R; sub new { bless {}, shift } sub name { 1 } sub other { 2 } 1;\n" }

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh "use lib '$lib'; use R;\n$src"; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

for my $body (
    q{print R->can("name") ? "ok\n" : "not ok\n";},
    q{print R->can("nope") ? "not ok\n" : "ok\n";},
    q{my $m = $ENV{M} // "other"; print R->can($m) ? "ok\n" : "not ok\n";},
    q{my $o = R->new; print $o->can("name") ? "ok\n" : "not ok\n";},
) {
    my $r = tap("$body\n");
    is $r->{verdict}, 'SAME', "as perl through T2: $body" or diag $r->{why} // explain $r;
}

# BY A NAME NOT KNOWN HERE can() answers from the stash by name (an unreached
# sub's body is not loaded); calling what it hands back is refused, not wrong.
my $r = tap(q{my $m = $ENV{M} // "other"; my $c = R->can($m); print $c->(), "\n";} . "\n");
is $r->{verdict}, 'REFUSED', 'a call of what can() handed back by a computed name: refused';
like $r->{why}, qr/can\(\) may hand back a sub not loaded/, '... saying why';

done_testing;
