# ABOUTME: an array or hash whole-assigned (`@p = ()`, `%h = ()`) is a new version of it, merged
# ABOUTME: at a join or round a loop; a `my` one first needed in an arm or a loop body is made where it stands.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

# run($cmd) -> [stdout, stderr, exit code]
sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

# lower($src) -> (ll or undef, the .pl, why)
sub lower ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    return ($ll, $pl, $err // $u->{path_why} // $u->{err});
}

# AS PERL: each through T2 alone, its output, message and exit code perl's.
for my $case (
    # A WHOLE ASSIGN IN A LOOP is a new version each pass, made where it stands.
    [ q{my %h = (a => 1); my @a = (1); for my $i (1 .. 3) { %h = (); @a = (); $h{$i}++; push @a, $i; print join(",", keys %h), scalar(@a), "\n" }},
      'a hash and an array emptied each pass' ],
    [ q{my @p; for my $i (1 .. 2) { @p = (); for my $j (1 .. 2) { push @p, "$i$j" } print "@p\n" } print "@p\n";},
      'an array emptied in a loop body, filled in an inner loop' ],
    [ q{my %h = (z => 0); for my $i (1 .. 3) { if ($i == 2) { %h = () } $h{$i} = 1; print join(",", sort keys %h), "\n" }},
      'a hash emptied in an arm, written after the join' ],
    [ q{my @p = (1); for my $i (1 .. 3) { push @p, $i; @p = () if $i == 2; print scalar(@p), "\n" }},
      'an array pushed to each pass, emptied in an arm' ],
    [ q{my @a = (1); for my $i (1 .. 3) { @a = ($i, @a) if $i > 1; print "@a\n" }},
      'an array whole-assigned from itself in an arm' ],
    [ q{my @p; for my $x ([1, 2], [3]) { if (@p) { } else { @p = $x->@* } } print "@p\n";},
      'an array whole-assigned in a loop, read whole after it' ],
    [ q{my %h = (a => 1); for my $i (1 .. 2) { %h = (b => $i) if $i == 2; } my @l = %h; print "@l ", scalar(keys %h), " ", join(",", %h), "\n"; print %h, "\n";},
      'a hash whole-assigned in a loop, read whole after it' ],
    [ q{sub f { my @body; my @params; my $name; for my $x (@_) { if (!ref $x) { next if $x eq 'sub'; $name = $x; } elsif (ref $x eq 'ARRAY') { if (@params) { @body = $x->@* } else { @params = $x->@* } } } return "$name|@params|@body"; } print f("sub", "n", [1, 2], [3, 4, 5]), "\n";},
      'two arrays whole-assigned in nested arms of a loop body' ],
    # A BUILTIN'S LIST (sort's, reverse's, keys') as the new value: a list of its own.
    [ q{sub f { my @r; for my $x (@_) { @r = sort { $a <=> $b } (@r, $x) } return "@r" } print f(3, 1, 2), "\n";},
      'an array sorted into itself each pass' ],
    [ q{my @r = (9); for my $x (3, 1) { @r = reverse(@r, $x) if $x; push @r, 0 } print "@r\n"; my %k = (a => 1); my @ks; for my $i (1 .. 2) { @ks = keys %k; $k{"b$i"} = $i } print scalar(@ks), "\n";},
      'an array reversed into itself in an arm, keys each pass' ],
    # A MERGE OF AN ARRAY THROUGH A REFERENCE and a list of its own.
    [ q{sub f { my ($r, $e) = @_; my $o = ""; for my $s ($e ? @{ $r->{s} // [] } : ()) { $o .= $s } return $o } print f({s=>[1,2]}, 1), f({}, 1), f({s=>[3]}, 0), "\n";},
      'a choice of an array through a reference or none' ],
    # A `my` AGGREGATE MADE BEFORE A LOOP, FIRST NEEDED IN ITS BODY: made once.
    [ q{my %h = (a => [1]); for my $i (1 .. 2) { $h{$i} = 1 } print join(",", sort keys %h), "\n";},
      'a hash made before a loop, stored to in it' ],
    [ q{my @q = ([1]); for my $i (1 .. 2) { push @q, $i } print scalar(@q), "\n";},
      'an array made before a loop, pushed to in it' ],
    [ q{my %in = (a => [[1, 2], 3], b => [4]); my @seen; for my $d (qw(a b)) { push @seen, $d . scalar(@{ $in{$d} }) . $in{$d}[-1] } print "@seen\n";},
      'a hash made before a loop, read in it' ],
    [ q{my $x = shift // 1; my @a = ($x); if ($x) { push @a, 3 } print "@a\n";},
      'an array made before an if, pushed to in its arm, read after' ],
    [ q{for my $i (1 .. 2) { my @a = ($i, 1); my %h = (k => $i); print "@a $h{k}\n" }},
      'an array and a hash of the loop body\'s own values' ],
    [ q{my @p = (0); for my $i (1 .. 3) { @p = (); if ($i > 1) { push @p, $i } print scalar(@p), "@p\n" }},
      'an array emptied each pass, pushed to in an arm, read after the join' ],
    # WRITTEN IN PLACE THROUGH A MERGE of its versions (`push @p` where @p is
    # the loop's merge of it and of `@p = ()`): B::SoN gives the push the
    # memory it runs at, the version after it, so a count after it reads it
    # (perl's "1 3| 5", pvm c140; before, "2| 1" was refused by name).
    [ q{my @p; my $o = ""; for my $pos (0 .. 5) { push @p, $pos if $pos % 2; if (@p > 1) { $o .= "@p|"; @p = () } } print "$o @p\n";},
      'an array emptied in an arm of a loop body, pushed to through the merge' ],
    [ q{my @q; for my $i (1 .. 4) { if ($i % 2) { push @q, $i } if (@q > 1) { print "@q\n"; @q = () } }},
      'an array pushed to in one arm, emptied in another' ],
    [ q{sub f { my @p; my $out = ""; for my $pos (0 .. 5) { push @p, $pos if $pos % 2; if (@p > 1) { for my $s (@p) { $out .= $s } $out .= "|"; @p = (); } } return "$out @p" } print f(), "\n";},
      'pvm c140: in a sub, walked before it is emptied' ],
    [ q{my @p; my $o = ""; for my $pos (0 .. 5) { unshift @p, $pos if $pos % 2; if (@p > 1) { $o .= "@p|"; @p = () } } print "$o @p\n";},
      'unshift onto the merge' ],
    [ q{my @p; my $o = ""; for my $pos (0 .. 5) { pop @p if $pos % 2; $o .= scalar(@p); if (@p < 1) { @p = (4, 5) } } print "$o @p\n";},
      'pop from the merge' ],
    [ q{my @p; my $o = ""; for my $pos (0 .. 5) { my $x = shift @p; $o .= ($x // 'u') . scalar(@p); if (!@p) { @p = (4, 5) } } print "$o @p\n";},
      'shift from the merge' ],
    [ q{my @p = (1, 2, 3); my $o = ""; for my $pos (0 .. 4) { $#p = 0 if $pos % 2; $o .= scalar(@p); if (@p < 2) { @p = (4, 5, 6) } } print "$o @p\n";},
      'its last index stored through the merge' ],
    # A LIST OF ITS OWN (no variable's) needed in an arm: made there.
    [ q{sub f { my $out = ""; for my $k (qw(x y)) { my @p = grep { $_ ne $k } qw(a b c); next unless @p; for my $q (@p[1 .. $#p]) { $out .= "$k$q " } } $out } print f(), "\n";},
      'a slice walked in an arm' ],
) {
    my ($src, $name) = @$case;
    my ($ll, $pl, $why) = lower($src);
    ok(defined $ll, "$name: lowered through T2") or diag $why;
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

done_testing;
