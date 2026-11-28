# ABOUTME: Chalk::IR::Transform::UnreadPhis removes the value Phis no live node reads (a
# ABOUTME: try/catch statement's value) and keeps every Phi a node reads, through other Phis.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Scalar::Util qw(blessed refaddr);
use Chalk::IR::Serialize::JSON;
use Chalk::IR::Transform::UnreadPhis;

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

sub graphs ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    return Chalk::IR::Serialize::JSON::from_json($json);
}
# value_phis($graph) -> the value Phis its Regions and Loops say merge there
sub value_phis ($g) {
    my %seen;
    return grep { !$seen{ refaddr($_) }++ } map {
        my $r = $_;
        grep { blessed($_) && $_->operation eq 'Phi' && !$_->memory && refaddr( $_->region ) == refaddr($r) } ( $r->consumers // [] )->@*
    } grep { $_->operation =~ /\A(?:Region|Loop)\z/ } $g->component;
}

# reads($g) -> { refaddr => 1 } of every node a node of the graph reads
sub reads ($g) { return { map { refaddr($_) => 1 } grep { blessed($_) } map { $_->inputs->@* } $g->component } }

# A TRY/CATCH STATEMENT'S VALUE is a Phi of the try arm's last statement and
# the catch arm's; nothing reads it. The loader runs the pass: every value Phi
# left at a merge is one a node reads (the eval's own `$@` test keeps its).
my $g = graphs('use v5.42; sub r ($s) { return (1, 2) } try { my ($o, $s) = r("a"); say "$s"; } catch ($e) { print $e; }')->{'main::__PROGRAM__'};
my $r = reads($g);
my @phis = value_phis($g);
ok scalar(@phis), 'the try keeps a value Phi it reads';
is scalar( grep { !$r->{ refaddr($_) } } @phis ), 0, 'no value Phi nothing reads is left at a merge';

# THE PASS AGAIN finds nothing: it removed what it could.
my $pass = Chalk::IR::Transform::UnreadPhis->new;
$pass->run($g);
is $pass->removed, 0, 'run again: none removed';
is scalar( () = value_phis($g) ), scalar(@phis), 'every read Phi kept';

done_testing;
