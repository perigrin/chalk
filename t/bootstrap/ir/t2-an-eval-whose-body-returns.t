# ABOUTME: A `return` inside a block eval leaves the eval (B::SoN: its join has a way
# ABOUTME: in per return). Not lowered yet: refused by name, never a crash or a wrong answer.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Pipeline;

sub lower ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json,not_package=SoN $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        return ([ 'main::__PROGRAM__', $g->returns->[0] ]);
    };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    return $err // ( $units->[0]{ok} ? 'lowered' : $units->[0]{err} );
}

for my $src (
    q{sub f { my $x = shift; my $w = eval { return "none" unless $x; "got $x" }; "<$w>" } print f(1), f(0), "\n";},
    q{sub f { my $n = 0; my $w = eval { for my $i (1 .. 5) { $n++; return "at $i" if $i == 3 } "end" }; "$w $n" } print f(), "\n";},
) {
    like lower($src), qr/GAP: .*(?:an eval Region of more than one way in|a block eval whose body returns)/, "refused by name: $src";
}

done_testing;
