# ABOUTME: s/// through T2: the pattern's own graph (the subst flavor) copies the subject
# ABOUTME: around each match with the replacement in place; in place or as a value.
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
    '(my $t = $s) =~ s/\d+/#/g; print "$t $s\n";',
    '$s =~ s/b/B/; print "$s\n";',
    '$s =~ s/\d/-/g; print "$s\n";',
    'my $u = $s =~ s/c/C/r; print "$u $s\n";',
    'my $u = $s =~ s/(\d)(\d)/$2$1/r; print "$u\n";',
    '(my $t = $s) =~ s/(b)(\d+)/[$2:$1]/; print "$t\n";',
    'my $n = ($s =~ s/b/B/); my $m = ($s =~ s/q/Q/); print "[$n][$m] $s\n";',
    'my $c = ($s =~ s/\d//g); print "$c $s\n";',
    '(my $t = $s) =~ s/x*/-/g; print "$t\n";',
    '(my $t = $s) =~ s/^/>/; print "$t\n";',
    '$s =~ s/(\d+)$//; print "$s\n";',
    '(my $t = $s) =~ s/(\d+)/$1*2/e; print "$t\n";',
    'my $u = $s =~ s/(\d+)/$1+1/er; print "$u $s\n";',
) {
    my $r = tap("my \$s = \$ENV{S} // 'a1b22c333';\n$body\n");
    is $r->{verdict}, 'SAME', $body or diag $r->{why} // explain $r;
}

# A REPLACEMENT MADE PER MATCH with /g: B::SoN computes it once (from one
# match), so it is refused, never spliced in at every match.
my $r = tap(qq{my \$s = \$ENV{S} // 'a1b2';\n(my \$t = \$s) =~ s/(\\d)/<\$1>/g;\nprint "\$t\\n";\n});
is $r->{verdict}, 'REFUSED', 's///g with a replacement made per match: refused' or diag explain $r;
like $r->{why}, qr/per match|once|m\/\/g in scalar context|pos\(\)/, '... saying why (B::SoN makes it by a /g match of its own)';

done_testing;
