# ABOUTME: perl's length of undef is undef (5.12 on): the wire stamps Length Maybe[Int],
# ABOUTME: T1 keeps that stamp, and T2 answers each program as perl does.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::LLI;
Chalk::CodeGen::Harness::LLI->lli;
require Chalk::CodeGen::Harness::T2Case;
require Chalk::CodeGen::Pipeline;
use File::Temp qw(tempfile);

sub perl_says ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return scalar qx($^X $pl 2>/dev/null);
}

# The loaded Length keeps the wire's Maybe[Int]: a later pass that re-stamps
# it Int claims length(undef) is a number.
sub length_stamps ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json,not_package=SoN $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        return ([ 'main::__PROGRAM__', $g->returns->[0] ]);
    };
    my (undef, $graphs) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    return [ map { $_->stamp } grep { $_->operation eq 'Length' }
             grep { ref && eval { $_->can('operation') } }
             map  { ref eq 'ARRAY' ? @$_ : $_ } $graphs->{'main::__PROGRAM__'}->nodes ];
}
is_deeply( length_stamps(q{my $u; my $l = length($u); print defined $l ? "D" : "U";}),
    ['Maybe[Int]'], 'a Length of what may be undef keeps its Maybe[Int] stamp through T1' );
# ...and of what cannot be undef is an Int: undef comes only from an undef operand.
is_deeply( length_stamps(q{my $s = "foo"; print(($s =~ /(o+)/ ? length($1) : 0), "\n");}),
    ['Int'], 'a Length of a Str is an Int' );

# Each program's answer is perl's, through T2 alone.
for my $src (
    q{my $l = length $ENV{NOPE}; print defined $l ? "D" : "U";},
    q{my $u; my $l = length($u); print defined $l ? "D" : "U", "\n";},
    q{my $s = "abc"; my $l = length($s); print defined $l ? "D$l" : "U", "\n";},
    q{my $s = "foo"; print(($s =~ /(o+)/ ? length($1) : 0), "\n");},
) {
    my $r = Chalk::CodeGen::Harness::T2Case::run_case({ id => "length:$src", src => $src, want => perl_says($src) });
    is($r->{verdict}, 'SAME', $src) or diag( $r->{why} // "got: $r->{got}" );
}

done_testing;
