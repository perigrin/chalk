# ABOUTME: B::SoN's verifier (SoN::Verify, found through PERL5_SON_LIB) over the wire v2 of chalk's
# ABOUTME: lib/**/*.pm and of the audit probes: no violation of any rule, but those held by name.
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
#   EVERY RULE IS HARD (stage 10): a violation of any rule SoN::Verify
#   names -- V1-V11, memory-as-value -- fails, but those %HELD names, each
#   with why. (Until stage 10 V8's other rules and V9 were held to a
#   baseline file, empty since stage 8: deleted.)
#
# A WIRE IS CACHED (it takes B::SoN about an hour over chalk's lib) under
# CHALK_WIRE_CACHE (default: a directory in the temp dir), keyed by the
# producer's content (every .pm under PERL5_SON_LIB) and the file's; a lib
# module's wire also by the content of each chalk module it follows. A wire
# that timed out or wrote no JSON is a failure, never a missing row.
#
#   SON_WIRE_JOBS=N              compiles at a time (default 2)
#   SON_WIRE_TIMEOUT=S           per compile (default 900)
my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/SoN/Verify.pm";
unshift @INC, $SON;
require SoN::Verify;

# A VIOLATION HELD, by file, graph and rule, each with why it is
# not fixed yet. One that no longer occurs is printed: take it out.
my %HELD = (
    # (probes pl13 and aun17f, a list assignment to package scalars that is
    # its sub's value, were held here as `record`: B::SoN gives the Return
    # its two readings now, the targets after it and the right side's count)
    # (DynaLoader's two, held here as "not traced yet", are gone: perl
    # compiles it before B::SoN turns the peephole off, and B::SoN now
    # refuses its aelemfast by name -- the producer's
    # t/wire-a-fused-element-op-is-refused.t)
    # The goal audit's probes (2026-11-22), as the producer's ratchet holds them:
    't/data/audit-probes/aun6.pl:main::bump read-unversioned:through-ref' =>
        'a compound assignment through a symbolic reference (`${"main::g"} += 10`): its read of the package scalar names '
      . 'no version; T2 gives perl\'s answer (the read is its own store\'s operand), B::SoN should version it -- open',
    't/data/audit-probes/aun5d.pl:main::__PROGRAM__ effect-floating' =>
        'a division that may fault after a `next unless` guard in a loop body floats: the rest of the body is walked as '
      . 'an arm, where B::SoN does not pin; T2 makes it at its use, after the guard -- open, B::SoN should pin it',
    # (rea12, held here at 8f6e3670, is gone: B::SoN reads @a at its store's
    # version, and T2 returns a package array)
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
            . "-MO=-q,SoN,json,not_package=SoN '$file' > '$base.tmp$$' 2>/dev/null" );
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

# verify each set: every violation is hard, but those %HELD names
my ( @hard, @dropped, %held );
for my $f ( @lib, @probes ) {
    my $w = cached($f);
    unless ($w) { push @dropped, $f; next }
    die "$f: B::SoN wrote wire version " . ( $w->{version} // 1 ) . ", not 2\n" unless ( $w->{version} // 1 ) == 2;
    for my $v ( SoN::Verify::verify($w)->{violations}->@* ) {
        my $k = "$f:$v->{graph} $v->{rule}";
        if ( $HELD{$k} ) { $held{$k} = 1; next }
        push @hard, "$f: $v->{graph}#$v->{node} $v->{op} $v->{rule}: $v->{detail}";
    }
}

is_deeply( \@dropped, [], 'every file has a wire (none timed out or wrote no JSON)' );
is_deeply( \@hard, [], 'no violation of any rule (but those %HELD names)' ) or diag join "\n", @hard[ 0 .. ( $#hard < 30 ? $#hard : 30 ) ];
diag "held, and no longer seen (take it out of %HELD): $_" for grep { !$held{$_} } sort keys %HELD;

done_testing;
