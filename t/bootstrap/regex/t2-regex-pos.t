# ABOUTME: m//g in scalar context through T2: each variable keeps its pos() -- where
# ABOUTME: the next match starts, what \G matches -- reset when the variable is written.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}
for my $body (
    'while ($s =~ /(\d+)/g) { print "$1@", pos($s), "\n" }',
    'my $n = 0; while ($s =~ /x*/g) { $n = $n + 1 } print "$n\n";',
    'if ($s =~ /b/g) { print pos($s), "\n" } if ($s =~ /c/g) { print pos($s), "\n" }',
    '$s =~ /b/g; $s =~ /q/g; print defined pos($s) ? "d" : "u", "\n";',
    '$s =~ /b/g; $s =~ /q/gc; print pos($s), "\n";',
    '$s =~ /b/g; $s = "zz9"; print defined pos($s) ? "d" : "u", "\n";',
    # (a join after it takes the match as its MEMORY, not an argument: scalar still)
    'my @f = split / /, "p q"; $s =~ /b/g; my $at = pos($s); print "@f $at\n";',
    'pos($s) = 3; if ($s =~ /\G(\w)/gc) { print "$1 ", pos($s), "\n" } $s =~ /\Gzz/gc; print pos($s), "\n";',
    # a lexer: \G where the last token ended, /gc to try the next kind
    'my @t; my $go = 1; while ($go) { if ($s =~ /\G(\d+)/gc) { push @t, "n$1" } elsif ($s =~ /\G([a-z])/gc) { push @t, "w$1" } else { $go = 0 } } print "@t\n";',
) {
    my $r = tap("my \$s = \$ENV{S} // 'a1b22c333';\n$body\n");
    is $r->{verdict}, 'SAME', $body or diag $r->{why} // explain $r;
}

done_testing;
