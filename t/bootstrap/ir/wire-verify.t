# ABOUTME: B::SoN's verifier (SoN::Verify, found through PERL5_SON_LIB) over the wire v2 of chalk's
# ABOUTME: lib/**/*.pm and of the audit probes: no V1-V5 or V7 violation; the rest held to a baseline.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use JSON::PP ();
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Spec;

# WHY (wire v2 plan, stage 5; section 8.2). The memory rules the producer is
# held to are checked on the wires of chalk's own code and of the probes in
# chalk's suite too -- by the producer's one implementation of them, not a
# second copy here ("two lists drift").
#
#   V1-V5, V7  mem-in-not-version, version-off-chain, write-unreachable,
#              control-sink, memory-order-disagrees, record: none.
#   the rest   (V6 read-unversioned:*, V8 phi-*, V9 control-fork): held to
#              t/data/wire-verify-v2-baseline.tsv -- the probes by their totals,
#              chalk's lib per graph (a recorded graph may not rise; one not
#              recorded is printed: lib changes with every chalk stage). Stage 7
#              takes V6 to zero, stage 8 the eval joins' phi-arity.
#
# A WIRE IS CACHED (it takes B::SoN about an hour over chalk's lib) under
# CHALK_WIRE_CACHE (default: a directory in the temp dir), keyed by the
# producer's content (every .pm under PERL5_SON_LIB) and the file's; a lib
# module's wire also by the content of each chalk module it follows. A wire
# that timed out or wrote no JSON is a failure, never a missing row.
#
#   CHALK_WIRE_VERIFY_UPDATE=1   rewrite the baseline from this run
#   SON_WIRE_JOBS=N              compiles at a time (default 2)
#   SON_WIRE_TIMEOUT=S           per compile (default 900)
my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/SoN/Verify.pm";
unshift @INC, $SON;
require SoN::Verify;

my %HARD = map { ( $_ => 1 ) } qw(mem-in-not-version version-off-chain write-unreachable control-sink memory-order-disagrees record);
my $BASELINE = 't/data/wire-verify-v2-baseline.tsv';
# A V1-V5 OR V7 VIOLATION HELD, by file, graph and rule, each with why it is
# not fixed yet. One that no longer occurs is printed: take it out.
my %HELD = (
    't/data/audit-probes/pl13.pl:main::sw record' =>
        'a list assignment to package scalars that is its sub\'s value: its EntryWrites store, and the Assign is '
      . 'the value (a list in list context, the right side\'s count in scalar), on neither chain; what node that '
      . 'value is wants a design (T2 refuses it by name: "the value of a list assignment to scalars")',
    # (perl's own DynaLoader, which chalk's runtime module follows)
    map( { ( "lib/Chalk/Bootstrap/Runtime.pm:$_ record" =>
        'an Assign of @isa alone, on neither chain, beside `local *isa = *{"$module\\::ISA"}; local @isa = (...)`: '
      . 'a v1 floating store the v2 writer calls a record; small programs of that shape do not reproduce it, not traced yet' ) }
        qw(DynaLoader::bootstrap DynaLoader::bootstrap_inherit) ),
);
my $jobs     = $ENV{SON_WIRE_JOBS}    // 2;
my $limit    = $ENV{SON_WIRE_TIMEOUT} // 900;

# the producer's content, every module of it
my $producer = do {
    my @pm;
    my $walk;
    $walk = sub ($d) {
        opendir my $dh, $d or return;
        for my $e ( sort readdir $dh ) {
            next if $e =~ /\A\./;
            my $p = "$d/$e";
            if    ( -d $p )        { $walk->($p) }
            elsif ( $p =~ /\.pm\z/ ) { push @pm, $p }
        }
    };
    $walk->($SON);
    sha256_hex( map { ( $_ =~ s/\A\Q$SON\E//r, slurp($_) ) } @pm );
};
my $CACHE = ( $ENV{CHALK_WIRE_CACHE} // File::Spec->catdir( File::Spec->tmpdir, "chalk-wire-verify-$<" ) ) . "/$producer";
make_path($CACHE);

sub slurp ($f) { open my $fh, '<:raw', $f or return ''; local $/; my $s = readline($fh); return $s // '' }
my %SHA;
sub sha_of ($f) { return $SHA{$f} //= sha256_hex( slurp($f) ) }

# The chalk modules a wire followed (a graph's `module`), as lib/ files.
sub deps_of ($w) {
    my %d;
    for my $g ( values +( $w->{methods} // {} )->%* ) {
        my $m = ref $g eq 'HASH' ? $g->{module} : undef;
        next unless defined $m && $m =~ /\AChalk::/;
        my $f = 'lib/' . ( $m =~ s{::}{/}gr ) . '.pm';
        $d{$f} = 1 if -f $f;
    }
    return sort keys %d;
}

# cached($file) -> the decoded wire, when the cache holds one for this content.
my $json = JSON::PP->new->utf8->canonical;
sub cached ($file) {
    my $base = "$CACHE/" . sha_of($file);
    my $meta = eval { $json->decode( slurp("$base.deps") ) } or return undef;
    return undef if grep { sha_of($_) ne $meta->{$_} } keys %$meta;
    return eval { $json->decode( slurp("$base.json") ) };
}

# compile($file): B::SoN's wire v2 of $file into the cache (nothing on failure).
sub compile ($file) {
    my $base = "$CACHE/" . sha_of($file);
    my $rc = system( "ulimit -v 4000000; PERL_HASH_SEED=0 /usr/bin/timeout $limit $^X -I$SON -Ilib "
            . "-MO=-q,SoN,json,wire=2,not_package=SoN '$file' > '$base.tmp$$' 2>/dev/null" );
    my $exit = $rc >> 8;
    my $w = !( $exit == 124 || ( $exit > 128 && $exit < 160 ) || ( $rc & 127 ) ) && -s "$base.tmp$$"
        ? eval { $json->decode( slurp("$base.tmp$$") ) } : undef;
    unless ($w) { unlink "$base.tmp$$"; return }
    open my $o, '>', "$base.deps.tmp$$" or die $!;
    print $o $json->encode( { map { ( $_ => sha_of($_) ) } deps_of($w) } );
    close $o;
    rename "$base.tmp$$", "$base.json";
    rename "$base.deps.tmp$$", "$base.deps";
}

my @lib    = do { my @f; my $w; $w = sub ($d) { opendir my $dh, $d or return; for ( sort readdir $dh ) { next if /\A\./; my $p = "$d/$_"; -d $p ? $w->($p) : /\.pm\z/ ? push( @f, $p ) : () } }; $w->('lib'); @f };
my @probes = sort glob 't/data/audit-probes/*.pl';
ok( scalar(@lib) > 100 && scalar(@probes) > 100, sprintf( 'the sets: %d lib modules, %d probes', scalar @lib, scalar @probes ) );

# fill the cache, $jobs at a time
{
    my %kids;
    for my $f ( grep { !cached($_) } @lib, @probes ) {
        if ( keys %kids >= $jobs ) { delete $kids{ waitpid -1, 0 } }
        my $pid = fork // die "fork: $!";
        if ( !$pid ) { compile($f); exec '/bin/true' }
        $kids{$pid} = 1;
    }
    waitpid $_, 0 for keys %kids;
}

# verify each set: { hard => [violation lines], probes => {rule => n}, lib => {graph => {rule => n}} }
my ( @hard, @dropped, %total, %graph, %held );
for my $set ( [ lib => \@lib ], [ probes => \@probes ] ) {
    my ( $name, $files ) = @$set;
    for my $f (@$files) {
        my $w = cached($f);
        unless ($w) { push @dropped, $f; next }
        die "$f: B::SoN wrote wire version " . ( $w->{version} // 1 ) . ", not 2\n" unless ( $w->{version} // 1 ) == 2;
        my %here;
        for my $v ( SoN::Verify::verify($w)->{violations}->@* ) {
            if ( $HARD{ $v->{rule} } ) {
                my $k = "$f:$v->{graph} $v->{rule}";
                if ( $HELD{$k} ) { $held{$k} = 1; next }
                push @hard, "$f: $v->{graph}#$v->{node} $v->{op} $v->{rule}: $v->{detail}";
                next;
            }
            $total{$name}{ $v->{rule} }++;
            my $g = $v->{graph} eq 'main::__PROGRAM__' ? "$f:$v->{graph}" : $v->{graph};
            $here{$g}{ $v->{rule} }++;
        }
        next unless $name eq 'lib';
        # (a graph is in every wire that loads its module: the most one wire counts)
        for my $g ( keys %here ) {
            $graph{$g}{$_} = $here{$g}{$_} for grep { $here{$g}{$_} > ( $graph{$g}{$_} // 0 ) } keys $here{$g}->%*;
        }
    }
}

is_deeply( \@dropped, [], 'every file has a wire (none timed out or wrote no JSON)' );
is_deeply( \@hard, [], 'no V1-V5 or V7 violation (but those %HELD names)' ) or diag join "\n", @hard[ 0 .. ( $#hard < 30 ? $#hard : 30 ) ];
diag "held, and no longer seen (take it out of %HELD): $_" for grep { !$held{$_} } sort keys %HELD;

# THE BASELINE: `probes<TAB>RULE<TAB>N` and `lib<TAB>@GRAPH<TAB>rule=n,...`
my @now = (
    ( map { my $r = $_; "probes\t$r\t$total{probes}{$r}" } sort keys +( $total{probes} // {} )->%* ),
    ( map { my $g = $_; "lib\t\@$g\t" . join ',', map { "$_=$graph{$g}{$_}" } sort keys $graph{$g}->%* } sort keys %graph ),
);
if ( $ENV{CHALK_WIRE_VERIFY_UPDATE} ) {
    open my $o, '>', $BASELINE or die "$BASELINE: $!";
    print $o "# SoN::Verify on wire v2 (t/bootstrap/ir/wire-verify.t): the probes' totals per rule, chalk's lib\n",
             "# per graph (the most one wire counts). Rewritten by CHALK_WIRE_VERIFY_UPDATE=1; a row only falls.\n";
    print $o "$_\n" for @now;
    close $o;
    pass("$BASELINE rewritten");
    done_testing;
    exit;
}
my ( %want_total, %want_graph );
for ( split /\n/, slurp($BASELINE) ) {
    next if /\A#/ || !/\S/;
    my ( $set, $k, $v ) = split /\t/, $_, 3;
    if ( $set eq 'probes' ) { $want_total{$k} = $v; next }
    $want_graph{ $k =~ s/\A@//r } = { map { split /=/ } grep { length } split /,/, $v // '' };
}
ok( %want_total || %want_graph, "$BASELINE has rows" );
my @rose = map { "probes: $_ " . ( $want_total{$_} // 0 ) . " -> $total{probes}{$_}" }
    grep { $total{probes}{$_} > ( $want_total{$_} // 0 ) } sort keys +( $total{probes} // {} )->%*;
for my $g ( sort keys %graph ) {
    if ( !$want_graph{$g} ) { diag "lib: a graph not in the baseline: $g " . join ',', map { "$_=$graph{$g}{$_}" } sort keys $graph{$g}->%*; next }
    push @rose, map { "lib: $g $_ " . ( $want_graph{$g}{$_} // 0 ) . " -> $graph{$g}{$_}" }
        grep { $graph{$g}{$_} > ( $want_graph{$g}{$_} // 0 ) } sort keys $graph{$g}->%*;
}
is_deeply( \@rose, [], 'no rule above its baseline (V6, V8, V9)' );
my @fell = grep { ( $total{probes}{$_} // 0 ) < $want_total{$_} } sort keys %want_total;
diag "probes: below the baseline (lower it): @fell" if @fell;
done_testing;
