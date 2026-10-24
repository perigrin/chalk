# ABOUTME: An element read at a dynamic index or key may not be there: defined()
# ABOUTME: and // take its own defined bit, whatever the read is stamped.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# ANALYSIS TYPES A READ FROM WHAT THE CONTAINER HOLDS -- Int, for a list of
# Ints -- and a dynamic index or key can still miss. defined() over an Int
# is always true, so `defined $a[$i]` past the end said yes, and `$h{$k} //
# "u"` merged a Slot into an i64 phi (pre-existing at e1a15d3a; backlog
# 9c217485). Both now read the element's Slot for its defined bit.
for my $case (
    [ q{my @a = (1, 2); my $i = 5; $i = $i + 0; print defined($a[$i]) ? "d" : "u", "\n";}, "u\n", 'defined past the end' ],
    [ q{my @a = (1, 2); my $i = 5; $i = $i + 0; print $a[$i] // "u", "\n";}, "u\n", '// past the end' ],
    [ q{my %h = (a => 1); my $k = "zz"; $k = $k . ""; print defined($h{$k}) ? "d" : "u", "\n";}, "u\n", 'defined at a missing key' ],
    [ q{my %h = (a => 1); my $k = "zz"; $k = $k . ""; print $h{$k} // "u", "\n";}, "u\n", '// at a missing key' ],
    [ q{my %h = (a => 1); my $k = "a"; $k = $k . ""; print $h{$k} // "u", "\n";}, "1\n", '// at a key that is there' ],
    [ q{my %h = (a => 1); my $n = 1; $n = $n + 0; if ($n) { $h{b} = 5 } print $h{b} // "u", "\n";}, "5\n", 'a key stored in an arm' ],
    # A CONSTANT INDEX PAST THE END is stamped Undef, and was lowered as a
    # Slot that its Undef arm branched on: lli rejected it (9c217485).
    [ q{my @a = (1); if (defined $a[3]) { print "d\n" } else { print "u\n" }}, "u\n", 'defined at a constant index past the end' ],
    [ q{my @a = (1); my $n = $a[3]; print defined($n) ? "d" : "u", "\n";}, "u\n", 'held in a variable first' ],
    # A MISS IS CARRIED BY WHAT IT IS STORED IN: an element read stamped as
    # the container's values (Str here) read a missing key as a defined "".
    [ q{my %h = (k => "s"); my @a = (1, 2); $a[1] = $h{k}; $a[0] = $h{z}; print defined $a[0] ? "d" : "u", " $a[1]\n";}, "u s\n", 'stored into an array' ],
    [ q{my %h = (k => "s"); my %g; $g{x} = $h{z}; $g{y} = $h{k}; print exists $g{x} ? "e" : "n", defined $g{x} ? "d" : "u", "\n";}, "eu\n", 'stored into a hash' ],
    [ q{sub f { defined $_[0] ? "d" : "u" } my %h = (k => "s"); print f($h{z}), f($h{k}), "\n";}, "ud\n", 'handed to a call' ],
    [ q{sub f { defined $_[0] ? "d" : "u" } my %h = (k => "s"); my $v = $h{z}; my $w = $h{k}; print f($v), f($w), "\n"; our $p = $h{z}; print defined $p ? "d" : "u", "\n";}, "ud\nu\n", 'stored into a variable kept in memory, and a package scalar' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
