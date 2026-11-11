# ABOUTME: split through T2: the pattern's own graph (the split flavor) gives the fields,
# ABOUTME: by perl's rules for empty fields, limits, captures and awk mode.
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
sub show { 'print join("|", map { defined $_ ? "<$_>" : "u" } ' . $_[0] . '), "\n";' }
for my $c (
    [ 'a,b,,c,,',  'split /,/, $s' ],
    [ 'a,b,,c,,',  'split /,/, $s, -1' ],
    [ 'a,b,c',     'split /,/, $s, 2' ],
    [ 'abc',       'split //, $s' ],
    [ 'abc',       'split /x*/, $s' ],
    [ ',a',        'split /,/, $s' ],
    [ 'a,b',       'split /(,)/, $s' ],
    [ 'a,b-c',     'split /(-)|,/, $s' ],
    [ '',          'split /,/, $s' ],
    [ '  a b  c ', 'split " ", $s' ],
    [ "a\nb\n",    'split /^/, $s' ],
    [ 'abc',       'split /b*/, $s' ],
    [ 'k1=v1;k2=v2', 'split /[=;]/, $s' ],
) {
    my ( $subj, $expr ) = @$c;
    ( my $q = $subj ) =~ s/\n/\\n/g;
    my $r = tap(qq{my \$s = \$ENV{S} // "$q";\n} . show($expr) . "\n");
    is $r->{verdict}, 'SAME', "$expr on '$q'" or diag $r->{why} // explain $r;
}

# IN SCALAR CONTEXT split gives how many fields: not this list's (refused).
my $r = tap(qq{my \$s = \$ENV{S} // "a,b";\nmy \$n = split /,/, \$s;\nprint "\$n\\n";\n});
isnt $r->{verdict}, 'DIFFERS', 'split in scalar context: never a wrong count' or diag explain $r;

done_testing;
