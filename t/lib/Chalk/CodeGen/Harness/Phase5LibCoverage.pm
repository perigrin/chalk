# ABOUTME: Phase-5 self-hosting coverage measurement: how far each real chalk lib/
# ABOUTME: .pm file gets through B::SoN -> Pipeline (load + LLVM lower), scoped to its OWN units.
use 5.42.0;
use utf8;

package Chalk::CodeGen::Harness::Phase5LibCoverage;

use Scalar::Util qw(blessed);
use JSON::PP ();
use Chalk::CodeGen::Pipeline;

# measure_file($file, \%opts) -> \%result
#
# Runs one repo-relative lib/ .pm file through the full self-hosting pipeline and
# reports how far its OWN code (subs + feature-class methods declared IN this
# file) gets. The stages, in order, and where a file can stop:
#
#   NO_JSON    : B::SoN emitted no decodable JSON at all.
#   LOAD_FAIL  : the Pipeline's load stage died.
#   NO_OWN     : loaded, but this file contributed ZERO own units. With the chalk
#                lib dir on @INC (-I$libdir), real feature-class modules DO emit
#                their own methods, so NO_OWN now means the file genuinely defines
#                no translatable own units (rare); an emission miss is instead a
#                NO_JSON (the file's deps or structure defeated B::SoN entirely).
#   OK         : own units found; `own` and `lowered` count how many of them the
#                LLVM backend lowers without dying. `top_gap` is the most common
#                lowering-failure reason (the NO-REPR / unhandled-op GAP class).
#
# %opts:
#   perl => perl binary (default: this $^X)
#   son  => perl5-son lib dir (default: $ENV{PERL5_SON_LIB} or ~/dev/perl5-son/lib)
#   timeout => seconds for the B::SoN subprocess (default 90)
#
# The score to trend: sum(lowered) / sum(own) across files. It is ~0 today; the
# harness exists so that number is MEASURED, not guessed, and moves as the
# producer/backend close real-method GAPs.
sub measure_file {
    my ($class, $file, $opts) = @_;
    $opts //= {};
    my $perl = $opts->{perl} // $^X;
    my $son  = $opts->{son}
        // $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
    # The chalk lib dir MUST be on @INC for B::SoN: a real chalk module's own
    # `use Chalk::...` deps have to resolve or its feature-class body never fully
    # compiles and B::SoN emits NOTHING for the target (the earlier false
    # "NO_OWN / package= empties output" reading was this missing -Ilib, not a
    # producer limitation -- zhi 019f5da9).
    my $libdir = $opts->{libdir} // 'lib';
    my $to   = $opts->{timeout} // 90;

    my %res = (file => $file, stage => '?', own => 0, lowered => 0,
               gaps => 0, top_gap => '', fails => []);

    # The own packages/classes this file DECLARES -- the scoping key.
    my %own_pkg;
    open my $fh, '<', $file or do { $res{stage} = 'NO_FILE'; return \%res };
    while (<$fh>) { $own_pkg{$1} = 1 if /^\s*(?:package|class)\s+([\w:]+)/ }
    close $fh;

    # Stage 1: B::SoN JSON. -I$libdir so the file's own `use Chalk::...` resolve.
    # Count stderr GAP lines (skipped subs) as a signal.
    my $errf = "/tmp/p5lib_$$.err";
    my $json = qx($perl -I$son -I$libdir -MO=SoN,json $file 2>$errf);
    if (open my $eh, '<', $errf) { local $/; my $e = <$eh>; $res{gaps} = () = $e =~ /^B::SoN: skipped/mg; close $eh }
    unlink $errf;

    my $data = eval { JSON::PP->new->decode($json) };
    unless ($data) { $res{stage} = 'NO_JSON'; return \%res }

    # Stage 2/3: load, select this file's OWN units, lower each -- through the
    # ONE pipeline seam (Chalk::CodeGen::Pipeline), not an inline assembly.
    #
    # The selector is the scoping rule and stays here verbatim: feature-class
    # methods declared in this file (from the MOP) + free subs whose package is
    # own and are not class methods. The pipeline does not know what "own" means.
    my $select = sub ($graphs, $mop) {
        my @units;   # [label, return_node]
        my %is_method;
        if ($mop) {
            for my $cls ($mop->classes) {
                next unless $own_pkg{ $cls->name };
                for my $m ($cls->methods) {
                    $is_method{ $cls->name . '::' . $m->name } = 1;
                    my $g = eval { $m->graph } or next;
                    my ($ret) = grep {
                        blessed($_) && $_->can('operation') && $_->operation eq 'Return'
                    } @{ $g->returns // [] };
                    push @units, [ $cls->name . '::' . $m->name . ' [method]', $ret ] if $ret;
                }
            }
        }
        for my $name (sort keys %$graphs) {
            my ($pkg) = $name =~ /^(.+)::[^:]+$/;
            next unless $pkg && $own_pkg{$pkg};
            next if $is_method{$name};
            my $ret = eval { $graphs->{$name}->returns->[0] } or next;
            push @units, [ "$name [sub]", $ret ];
        }
        return @units;
    };

    # No program_mode: this harness measures whether a unit LOWERS AT ALL, and
    # never runs the emitted IR, so the return-value epilogue is irrelevant here.
    my ($units, undef, undef, $load_err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select);

    if ($load_err) { $res{stage} = 'LOAD_FAIL'; $res{err} = _clean($load_err); return \%res }
    unless (@$units) { $res{stage} = 'NO_OWN'; return \%res }

    # lower() takes the whole (shared) MOP, so a unit fails if ANY method the
    # backend reaches (incl. producer/dep methods in the shared MOP) GAPs -- the
    # honest all-or-nothing coupling of the current pipeline. Record the dominant
    # failure reason.
    $res{stage} = 'OK';
    my %gap_hist;
    for my $u (@$units) {
        $res{own}++;
        if ($u->{ok}) { $res{lowered}++; next }
        my $r = _clean($u->{err});
        push $res{fails}->@*, "$u->{label} -> $r";
        (my $bucket = $r) =~ s/'[^']*'/'X'/g;      # collapse the varying name
        $bucket = $1 if $bucket =~ /(GAP:[^.]{0,60})/;
        $gap_hist{$bucket}++;
    }
    ($res{top_gap}) = sort { $gap_hist{$b} <=> $gap_hist{$a} } keys %gap_hist;
    $res{top_gap} //= '';
    return \%res;
}

# aggregate(\@results) -> \%summary — sum across files for the trend number.
sub aggregate {
    my ($class, $results) = @_;
    my %s = (files => scalar @$results, own => 0, lowered => 0,
             by_stage => {}, gap_hist => {});
    for my $r (@$results) {
        $s{by_stage}{ $r->{stage} }++;
        $s{own}     += $r->{own}     // 0;
        $s{lowered} += $r->{lowered} // 0;
        $s{gap_hist}{ $r->{top_gap} }++ if ($r->{top_gap} // '') ne '';
    }
    $s{lower_pct} = $s{own} ? (100 * $s{lowered} / $s{own}) : 0;
    return \%s;
}

sub _clean {
    my ($e) = @_;
    $e //= 'unknown';
    $e =~ s/ at \S+ line \d+.*//s;   # strip the "at FILE line N" tail
    $e =~ s/\s+/ /g;
    $e =~ s/^\s+|\s+$//g;
    # Strip the non-ASCII em-dash the backend GAP message uses (ASCII source).
    $e =~ s/[^[:ascii:]].*//;
    return $e;
}

1;
