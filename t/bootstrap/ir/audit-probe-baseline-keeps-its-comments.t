# ABOUTME: tools/audit-probes.pl --update rewrites BASELINE.tsv: the comment lines after its header
# ABOUTME: (the probes left out as known WRONG pending a design decision, by class) survive it.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempdir);
use Chalk::CodeGen::Harness::AuditProbe qw(write_baseline read_baseline);

my $f = tempdir( CLEANUP => 1 ) . '/BASELINE.tsv';
open my $o, '>', $f or die $!;
print $o "# header\n# name\tverdict\twhy\nold\tSAME\t\n# left out (N3): yp06 yp07\n";
close $o;
write_baseline( { a1 => [ 'SAME', '' ], b2 => [ 'REFUSED', 'GAP: x' ] }, $f );
my $text = do { local ( @ARGV, $/ ) = $f; <> };
like( $text, qr/^# left out \(N3\): yp06 yp07$/m, 'the comment after the header is kept' );
is_deeply( [ sort keys read_baseline($f)->%* ], [qw(a1 b2)], '...and is no row' );
done_testing;
