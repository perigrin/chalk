# ABOUTME: a regex code block `(?{ ... })` runs where matching passes it -- a body
# ABOUTME: B::SoN lifts, called by the matcher: through B::SoN -> chalk -> lli == perl.
our $LAST_LL;
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

sub through_llvm ($src, $env) {
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
    $LAST_LL = $units->[0]{ll};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    local @ENV{ keys %$env } = values %$env;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return ($out, $pl);
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    return scalar qx($^X $pl 2>/dev/null);
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

for my $case (
    [ q{my $s = "abc"; my $k = 0; $s =~ /b(?{ $k = 5 })/; print "$k\n";}, 'a literal pattern' ],
    [ q{my $n = 0; my $r = qr/a(?{ $n = 7 })b/; my $s = "ab"; $s =~ $r; print "$n\n";}, 'a qr' ],
    [ q|my $s = "abc"; my $k = 0; $s =~ /b(?{ $k = length("}}}") })/; print "$k\n";|, 'braces in a string in the block' ],
    [ q{my $s = "ab"; my $t = ""; $s =~ /a(?{ $t .= "x" })b(?{ $t .= "y" })/; print "$t\n";}, 'two blocks, in order' ],
    [ q{my $s = "xxab"; my $t = 0; $s =~ /a(?{ $t = $t + 1 })b/; print "$t\n";}, 'run only where matching reaches it' ],
    [ q{my $s = "abc"; my $k = 0; my $hit = $s =~ /z(?{ $k = 5 })/ ? "y" : "n"; print "$hit$k\n";}, 'not run when matching never reaches it' ],
    [ q{my $s = "abc"; my $k = 0; $s =~ s{a}{ 3 }e; my $r = qr/c(?{ $k = 4 })/; $s =~ $r; print "$s $k\n";}, 'a qr applied to a variable an s///e rewrote' ],
    # PERL FINDS A LITERAL PATTERN BEFORE RUNNING ANY OF IT: one attempt,
    # where the whole literal first occurs -- so a block runs once on a hit and
    # never on a miss, however many starts a slide would try.
    [ q{my $t = 0; my $s = "aab"; $s =~ /a(?{ $t = $t + 1 })b/; print "$t\n";}, 'a literal pattern: one run, at the literal' ],
    [ q{my $t = 0; my $s = "xay"; my $h = $s =~ /a(?{ $t = $t + 1 })b/ ? 1 : 0; print "$h $t\n";}, 'a literal pattern that misses: no run' ],
    # A MATCH WHOSE BLOCK RUNS IS A NEW VERSION OF WHAT THE BLOCK WRITES: a read
    # after it is made there, not past a later store (review, 2026-11-04).
    [ q{my $t = 0; my $s = "ab"; $s =~ /a(?{ $t = 1 })/; my $u = $t + 1; $s =~ /a(?{ $t = 10 })/; print "$t $u\n";}, 'a read between two blocks' ],
    [ q{my $t = 0; my $s = "ab"; $s =~ /a(?{ $t = 1 })/; my $u = $t + 1; $t = 7; print "$t $u\n";}, 'a read before a later store' ],
    [ q{my $t = 0; my $s = "ab"; my $r = qr/a(?{ $t = $t + 1 })/; $s =~ $r; my $u = $t * 10; $s =~ $r; print "$t $u\n";}, 'a read between two qr matches' ],
    [ q{my @a = (1); my $s = "ab"; $s =~ /a(?{ push @a, 2 })/; my $n = scalar(@a); push @a, 3; print "$n\n";}, 'a count before a later push' ],
    [ q{my $t = "x"; my $s = "ab"; if ($s =~ /a(?{ $t = "y" })/) { my $old = $t; $t = "z"; print "$old\n" }}, 'a read in the arm the match guards' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# ANY OTHER PATTERN: how often a block runs is perl's optimizer's, so refused.
for my $src (q{my $t = 0; my $s = "azax"; $s =~ /a(?{ $t = $t + 1 })[xy]/; print "$t\n";},
              q{my $t = 0; my $s = "aaab"; $s =~ /a+(?{ $t = $t + 1 })b/; print "$t\n";}) {
    my ($got) = eval { through_llvm($src, {}) };
    like($@, qr/GAP: a regex code block in a pattern that is not all literal/, "refused by name: $src") or diag "got: " . ($got // 'undef');
}

# A BLOCK'S END IS FOUND BY BRACES AND QUOTES; a quote-like op (q(...)) can
# hide a `})` -- refused, not misread (review, 2026-11-04).
for my $src (q|my $t = ""; my $s = "ab"; my $h = $s =~ /a(?{ $t = join q(}), "(" })b/ ? 1 : 0; print "$h [$t]\n";|) {
    my ($got) = eval { through_llvm($src, {}) };
    like($@, qr/GAP: a regex code block with a quote-like op/, "refused by name: $src") or diag "got: " . ($got // 'undef');
}

done_testing;
