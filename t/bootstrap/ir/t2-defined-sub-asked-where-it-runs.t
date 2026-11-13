# ABOUTME: `defined &NAME` the program may change (B::SoN's SubDefined): answered as
# ABOUTME: compiled when no graph that may change it runs, refused by name when one does.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

# A MODULE SUB with an eval of code not known here, never called (Test::More's
# use_ok in a test that calls only is()): the answer holds. (The program's own
# subs are all loaded, so each counts as one that may run.)
my $lib = File::Temp::tempdir( CLEANUP => 1 );
open my $pm, '>', "$lib/EvalMod.pm" or die $!;
print $pm "package EvalMod; sub f { eval \$main::x } sub g { my \$c = sub { eval \$main::x }; \$c } sub h { 2 } 1;\n";
close $pm;
for my $src (
    qq{use lib "$lib"; use EvalMod; print defined &nope ? "y" : "n", defined &EvalMod::h ? "y" : "n", EvalMod::h(), "\\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

# A SUB NOT ON THE WIRE (a module B::SoN loaded but does not follow, as Errno
# for %!) runs only if a graph that runs calls it: by its name, or as a method
# of its short name on an invocant not known here.
{
    open my $pm2, '>', "$lib/unfollowed.pm" or die $!;
    print $pm2 q{package unfollowed; sub import { my $c = caller; no strict 'refs'; *{"${c}::z"} = sub { 1 } } 1;}, "\n";
    close $pm2;
}
my $r2 = tap(qq{use lib "$lib"; use unfollowed; print defined &nope ? "y" : "n", "\\n";\n});
is $r2->{verdict}, 'SAME', 'a sub not on the wire that nothing running calls' or diag $r2->{why} // explain $r2;

# THE RULE ITSELF, on a wire whose SubDefined names a sub not on it (Errno::import,
# in a program that loads Errno without following it): answered unless a graph
# that runs calls it -- here a method of its short name on an unknown invocant.
require Chalk::CodeGen::Pipeline;
require JSON::PP;
sub lower_naming ($src, $site) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    my $d = JSON::PP->new->decode( scalar qx($^X -I$SON -MO=-q,SoN,json,not_package=SoN $pl 2>/dev/null) );
    for my $m ( values %{ $d->{methods} } ) {
        $_->{fields}{unless} = [$site] for grep { $_->{op} eq 'SubDefined' } @{ $m->{nodes} };
    }
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail( JSON::PP->new->encode($d), $select, program_mode => 1 );
    return $err // ( $units->[0]{ok} ? 'lowered' : $units->[0]{err} );
}
is lower_naming(q{sub f { eval $main::x } print defined &nope ? "y" : "n", "\n";}, 'Ghost::import'), 'lowered',
    'a sub not on the wire, called by nothing that runs: answered';
like lower_naming(q{sub f { eval $main::x } sub g { my $o = shift; $o->import } print defined &nope ? "y" : "n", "\n";}, 'Ghost::import'),
    qr/defined &main::nope.*Ghost::import may run/, 'one whose short name a running graph calls as a method: refused';

# One that runs may change it: refused, naming the question.
for my $src (
    q{sub f { eval $main::x } f(); print defined &nope ? "y" : "n", "\n";},
    q{*late = sub { 1 }; print defined &late ? "y" : "n", "\n";},
    qq{use lib "$lib"; use EvalMod; EvalMod::f(); print defined &nope ? "y" : "n", "\\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'REFUSED', "refused: $src" or diag explain $r;
    like $r->{why} // '', qr/defined &(?:main::)?(?:nope|late)/, 'naming `defined &NAME`';
}

done_testing;
