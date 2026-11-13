# ABOUTME: a `local` element in a loop body is put back when a next or last leaves
# ABOUTME: the iteration, on that edge alone, as perl does at the block's end.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        ([ 'main::__PROGRAM__', $g->returns->[0] ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    return "REFUSED load: $err" if $err;
    return "REFUSED lower: $units->[0]{err}" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll}; close $lf;
    my $out = qx($LLI $ll 2>/dev/null);
    my $want = qx($^X $pl 2>/dev/null);
    return [ $out, $want ];
}

my $H = 'our %h = (k => 0); ';
for my $case (
    [ q{for my $i (1..3) { print "[$h{k}]"; local $h{k} = $i; next if $i == 2; print "$h{k} " } print "$h{k}\n";}, 'next if' ],
    [ q{for my $i (1..3) { print "[$h{k}]"; local $h{k} = $i; print "$h{k} "; next } print "$h{k}\n";}, 'a bare next' ],
    [ q{my $s = ""; for my $i (1..3) { local $h{k} = $i; last if $i == 2; $s .= $h{k} } print "$s $h{k}\n";}, 'last if' ],
    [ q{for my $i (1..3) { print "[$h{k}]"; local $h{k} = $i; next unless $i != 2; print "$h{k} " } print "$h{k}\n";}, 'next unless' ],
    [ q{for my $i (1..4) { print "[$h{k}]"; local $h{k} = $i; next if $i > 1 && $i < 4 && print("s"); print "$h{k} " } print "$h{k}\n";}, 'a chained guard' ],
    [ q{my $i = 0; while ($i < 3) { $i++; print "[$h{k}]"; local $h{k} = $i; next if $i == 2; print "$h{k} " } print "$h{k}\n";}, 'a while loop' ],
    [ q{for my $i (1..3) { print "[$h{k}]"; local $h{k} = $i; last if $i == 3; next if $i == 1; print "$h{k} " } print "$h{k}\n";}, 'last if, then next if' ],
    [ q{for my $i (1..4) { print "[$h{k}]"; local $h{k} = $i; next if $i == 1; next if $i == 3; print "$h{k} " } print "$h{k}\n";}, 'two next ifs' ],
    [ q{for my $i (1..3) { print "[$h{k}]"; local $h{k} = $i; print "$h{k} "; last if $i == 2 } print "$h{k}\n";}, 'a last if ending the body' ],
    [ q{my %n; for my $i (1..3) { print "[", exists $n{x} ? 1 : 0, "]"; local $n{x} = $i; next if $i == 2; print "$n{x} " } print exists $n{x} ? "x" : "-", "\n";}, 'a new key, then next' ],
) {
    my ($src, $name) = @$case;
    my $r = through_llvm($H . $src);
    if (!ref $r) { fail "$name: lowered"; diag $r; next }
    is $r->[0], $r->[1], "$name: perl's output";
}

# A `next` inside an if/else arm: perl's output, or refused by name -- never another.
for my $src (
    q{for my $i (1..3) { print "[$h{k}]"; local $h{k} = $i; if ($i == 2) { print "two "; next } print "$h{k} " } print "$h{k}\n";},
) {
    my $r = through_llvm($H . $src);
    ok !ref $r ? $r =~ /\AREFUSED (?:load|lower): .*GAP/ : $r->[0] eq $r->[1], 'a next in an arm: right or refused'
        or diag ref $r ? "got [$r->[0]] want [$r->[1]]" : $r;
}

done_testing;
