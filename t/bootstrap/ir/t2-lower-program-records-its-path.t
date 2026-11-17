# ABOUTME: lower_program records what T2 did with a unit -- took it, or refused it and why --
# ABOUTME: and the pipeline hands it on with the unit, so a corpus can count T2's share.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Pipeline;

sub unit_of ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    return $units->[0];
}

my $u = unit_of(q{my $x = 2; print $x + 1, "\n";});
is($u->{path}, 't2', 'a program T2 takes: path t2');
ok(!defined $u->{path_why}, 'and no reason');

$u = unit_of(q{eval q{die "boom\n"}; print "after: $@";});
is($u->{path}, 'refused', 'a program T2 refuses: path refused');
ok(!$u->{ok}, 'and nothing lowered it');
like($u->{err} // '', qr/\Q$u->{path_why}\E/, 'the unit fails with that same reason');
like($u->{path_why} // '', qr/\S/, 'with T2\'s reason');
done_testing;
