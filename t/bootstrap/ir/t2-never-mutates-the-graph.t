# ABOUTME: T2 reads B::SoN's graph and never changes it: when T2 falls back,
# ABOUTME: Context.pm lowers the same graph (a mutated Print once made two GAPs).
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use Scalar::Util qw(blessed refaddr);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

require Chalk::CodeGen::Pipeline;
require Chalk::Target::LLVM;
require Chalk::Target::LLVM::T2;

sub snapshot (@nodes) {
    return join "\n", map { refaddr($_) . ':' . join(',', map { blessed($_) ? refaddr($_) : 'u' } $_->inputs->@*) } @nodes;
}

for my $src (
    q{sub f { my $n = shift; return ($n, $n * 2) } print f(4), "\n";},
    q{my @a = (3, 1, 2); print sort @a; print "\n";},
    q{my %h = (a => 1); my @k = keys %h; print scalar(@k), "\n";},
    q{package N { sub new { bless {}, shift } sub v { 1 } } print N->new->v, "\n";},
) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my ($before, $after);
    Chalk::CodeGen::Pipeline->new->run_detail($json, sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0];
        my @nodes = map { Chalk::Target::LLVM::Context::_graph_component($_) } values %$graphs;
        $before = snapshot(@nodes);
        Chalk::Target::LLVM::T2->lower_program($ret, mop => $mop);
        $after = snapshot(@nodes);
        return ();
    }, program_mode => 1);
    is($after, $before, "T2 leaves the graph as it was: $src");
}

done_testing;
