# ABOUTME: The Perl subset Chalk compiles excludes tie, so no source under
# ABOUTME: lib/ may use the tie/untie/tied operators.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Find ();
use lib 'lib', 't/lib';

# WHY A GREP TEST AND NOT AN IR PASS. A tied variable's every read and write
# is a method call decided at RUNTIME, which is exactly the thing a
# stamp-and-lower pipeline cannot see: inference would type `$x` from its
# assignment and the backend would lower a load, while perl runs FETCH. There
# is no analysis that makes that safe, so the obligation is not "detect tie
# and GAP" -- it is that tie never enters the subset in the first place. A
# guard on the source is the whole mechanism; no IR pass needs to exist.
#
# OPERATOR FORM ONLY. `lib/` is full of the word "tie" as prose -- fourteen
# occurrences at this writing, every one of them "tie-break" in a comment
# about semiring disambiguation. A bare /\btie\b/ would flag all fourteen and
# be deleted within a week for crying wolf. These patterns match the operators
# where they are CALLED: `tie` and `untie` take a variable as their first
# argument, `tied` takes one and is usually read.

my @PATTERNS = (
    # tie VARIABLE, CLASSNAME, LIST   /   untie VARIABLE
    qr{ (?<! \w ) (?: un )? tie \s+ (?: my \s+ )? [\$\@\%] }x,
    # tied VARIABLE
    qr{ (?<! \w ) tied \s* \(? \s* [\$\@\%] }x,
);

sub offenders ($root) {
    my @hits;
    File::Find::find(
        {   no_chdir => 1,
            wanted   => sub {
                return unless -f $_ && /\.(?:pm|pl|t)\z/;
                open my $fh, '<:encoding(UTF-8)', $_ or return;
                my $file = $_;
                while ( my $line = <$fh> ) {
                    for my $re (@PATTERNS) {
                        next unless $line =~ $re;
                        push @hits, "$file:$.: $line" =~ s/\s+\z//r;
                        last;
                    }
                }
                close $fh;
            },
        },
        $root
    );
    return @hits;
}

# THE RED PROOF, run every time rather than recorded once. A grep test that
# matches nothing is indistinguishable from a grep test whose pattern is
# broken, and this one is guarding an empty set -- so it has to demonstrate on
# each run that it would still SEE a violation. The fixture below is what the
# assertion over lib/ is worth.
subtest 'the patterns catch tie where it is actually written' => sub {
    my $dir = tempdir( CLEANUP => 1 );
    my @fixtures = (
        [ 'plain.pm'  => qq{package P;\ntie my \@a, 'Foo';\n1;\n} ],
        [ 'scalar.pm' => qq{package S;\ntie \$x, 'Bar', 1;\n1;\n} ],
        [ 'hash.pm'   => qq{package H;\ntie %h, 'Baz';\n1;\n} ],
        [ 'untie.pm'  => qq{package U;\nuntie \@a;\n1;\n} ],
        [ 'tied.pm'   => qq{package T;\nmy \$o = tied(\@a);\n1;\n} ],
    );
    for my $f (@fixtures) {
        my ( $name, $body ) = $f->@*;
        open my $fh, '>:encoding(UTF-8)', "$dir/$name" or die;
        print $fh $body;
        close $fh;
    }

    my @hits = offenders($dir);
    is( scalar @hits, scalar @fixtures,
        'every operator form in the fixture is caught' );

    # And the prose that fills lib/ is NOT caught. A pattern that flags
    # "tie-break" gets switched off, which is the same as having no test.
    my $prose = tempdir( CLEANUP => 1 );
    open my $ph, '>:encoding(UTF-8)', "$prose/prose.pm" or die;
    print $ph join "\n",
        'package Q;',
        '# a deterministic tie-break picks left',
        '# resolves the tie by rank; see tie_log() and flush_tie_log()',
        'my $satiety = 1;   # substring, not the operator',
        '1;', '';
    close $ph;
    is_deeply( [ offenders($prose) ], [],
        'the word tie in prose and identifiers is not flagged' );
};

subtest 'lib/ uses no tie' => sub {
    my @hits = offenders('lib');
    is_deeply( \@hits, [],
        'no source under lib/ ties, unties, or reads a tied variable' )
        or diag( join "\n", @hits );
};

done_testing;
