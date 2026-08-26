# ABOUTME: Sub metadata reaches the backend registry; a sub never takes a vtable slot.
# ABOUTME: Emitting sub defines is gated off -- the inliner still owns every direct call.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON;
use Chalk::Target::LLVM;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "perl5-son not found at $SON"  unless -f "$SON/B/SoN.pm";

my $dir = tempdir(CLEANUP => 1);

# Compile $src through the producer and lower it, returning the emitted LLVM IR.
sub ll_for ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    # package=main is load-bearing here, not tidiness: an unfiltered compile
    # drags in the ambient module set, and one of THOSE classes GAPs first
    # ("MOP::Method 'is_known' body root ... NO representation"), so the test
    # would report a refusal that has nothing to do with its subject.
    my $json = qx{$PERL -I$SON -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my $mop = (values %$graphs)[0]->mop;
    my $g = $graphs->{'main::__PROGRAM__'} // $graphs->{'main::__main__'}
        or die "no entry graph for $name";
    my $ret = $g->returns->[0] or die "no Return node for $name";
    return Chalk::Target::LLVM->lower($ret, program_mode => 1,
        (defined $mop ? (mop => $mop) : ()));
}

my $SRC = <<'PERL';
use feature 'class';
no warnings 'experimental::class';
class Widget {
    field $n :param = 0;
    method get { $n }
    sub helper { 7 }
}
print Widget->new(n => 1)->get, "\n";
PERL

# 1c wires the METADATA CHANNEL: sub records reach the backend's registry
# instead of being recovered by scanning a graph. Emission of a `define` from
# them is deliberately GATED OFF -- the inliner still substitutes every
# direct-call body, so a define duplicates rather than enables. See the
# CHALK_EMIT_SUB_DEFINES notes in Target/LLVM.pm.
#
# I had assumed class subs were exempt from that (nothing dispatches them) and
# measured otherwise, which is why these assertions test the GATE rather than
# the define.
subtest 'a class sub does not emit a premature define' => sub {
    my $ll = eval { ll_for($SRC, 'clssub') };
    ok defined $ll, 'lowered' or do { diag $@; return };
    unlike $ll, qr/define\b[^\n]*Widget__helper/,
        'no define while the inliner still owns the call';
};

# The negative half, and the reason this is not just "add subs to the vtable":
# a sub has NO implicit invocant and is NOT dispatched, so it must never consume
# a vtable slot. A change that appended subs to {methods} would silently widen
# every vtable AND propagate through _flatten_inheritance to subclasses.
subtest 'a class sub does NOT take a vtable slot' => sub {
    my $ll = eval { ll_for($SRC, 'clsvt') };
    ok defined $ll, 'lowered' or do { diag $@; return };

    my ($vt) = grep { /^%Widget\.vt = type/ } split /\n/, $ll;
    ok defined $vt, 'Widget has a vtable' or return;
    # slot 0 is the class-name ptr; one method (`get`) means exactly 2 elements.
    my $slots = () = $vt =~ /i8\*/g;
    is $slots, 2,
        'vtable has class-name + ONE method slot (helper is not dispatched)'
        or diag $vt;
};

# THE MEASURED REASON the gate exists, pinned so step 5 inherits it as a known
# failure rather than rediscovering it. With defines enabled, a class sub
# carrying a string constant renders its globals TWICE -- once in the define,
# once in the inlined copy -- and lli rejects the whole module.
subtest 'enabling sub defines today collides with the inliner' => sub {
    local $ENV{CHALK_EMIT_SUB_DEFINES} = 1;
    my $src = <<'PERL';
use feature 'class';
no warnings 'experimental::class';
class W { field $n :param = 0; method get { $n } sub shout { print "S" } }
W::shout();
print W->new(n => 3)->get, "\n";
PERL
    my $ll = eval { ll_for($src, 'collide') };
    ok defined $ll, 'lowered' or do { diag $@; return };
    my @globals = grep { /^\@str_const_0 = / } split /\n/, $ll;
    is scalar @globals, 2,
        'the string global is emitted twice -- this is what step 5 must fix'
        or diag "count=" . scalar(@globals);
};

# THE `main` HALF IS DELIBERATELY NOT DONE, and this pins that rather than
# leaving it implied. main's subs ARE in the MOP (1b), but the INLINER still
# owns every direct call, so emitting a define for one duplicates the body
# instead of giving it a call path -- measured, corpus F9/F10/F11/F13 each
# printed their callee's output twice and the gate went 214 -> 207.
#
# main's class machinery must stay absent either way: it is never instantiated.
subtest 'main gets no class machinery, and no premature sub define' => sub {
    my $ll = eval { ll_for('sub helper { 7 } print helper(), "\n";', 'mainsub') };
    ok defined $ll, 'lowered' or do { diag $@; return };

    unlike $ll, qr/%main\.vt\b/,   'no vtable type for main';
    unlike $ll, qr/%main\.obj\b/,  'no object struct for main';
    unlike $ll, qr/\@main__vtable/,'no vtable global for main';

    # The staging assertion. Flip this to `like` in the step that retires the
    # inliner (plan step 5) -- that is the step that gives the define a caller.
    unlike $ll, qr/define\b[^\n]*\bmain__helper/,
        'no define for a file-level sub while the inliner still owns the call';
};

# The regression direction: a program with NO subs at all must emit exactly what
# it did before.
subtest 'a program with no subs is unchanged' => sub {
    my $ll = eval { ll_for('print 42, "\n";', 'nosubs') };
    ok defined $ll, 'lowered' or do { diag $@; return };
    unlike $ll, qr/%main\.vt\b/,      'still no vtable type for main';
    unlike $ll, qr/define[^\n]*main__/,'no stray sub defines';
};

# END TO END, which is what actually matters: with the gate off, both shapes
# still compile AND RUN correctly under lli. A pure class sub called from main
# resolves through the inliner exactly as before 1c.
subtest 'class and file-level subs still run correctly' => sub {
    my $src = <<'PERL';
use feature 'class';
no warnings 'experimental::class';
class W { field $n :param = 0; method get { $n } sub helper { 7 } }
print W::helper() + W->new(n => 3)->get, "\n";
PERL
    my $ll = eval { ll_for($src, 'e2e') };
    ok defined $ll, 'lowered' or do { diag $@; return };
    # 7 + 3 = 10, matching perl.
    unlike $ll, qr/define\b[^\n]*W__helper/, 'still no premature define';
    like $ll, qr/define i32 \@main\(/, 'the program entry is emitted';
};

# THE SHAPES $SRC DOES NOT COVER. `sub helper { 7 }` is the one benign case --
# never called, no string literal, no @_ -- so it dodges every way this step can
# break a program. Each of these regressed at some point during 1c and each is
# checked END TO END against perl rather than by inspecting IR text.
subtest 'declaring a class sub does not break the program' => sub {
    my %want = (
        # a string literal in the body: its globals must not collide with main's
        'sub label { "wid" }'                  => "5\n",
        # reads @_: has no bound argument outside an inline, so registering it
        # would refuse the whole program on a missing repr
        'sub twice { my $x = shift; $x * 2 }'  => "5\n",
        # the benign baseline, for contrast
        'sub helper { 7 }'                     => "5\n",
    );
    my $i = 0;
    for my $decl (sort keys %want) {
        $i++;
        my $src = <<"PERL";
use feature 'class';
no warnings 'experimental::class';
class W { field \$n :param = 0; method get { \$n } $decl }
print W->new(n => 5)->get, "\\n";
PERL
        my $ll = eval { ll_for($src, "decl$i") };
        ok defined $ll, "lowers with: $decl" or do { diag $@; next };
        # One definition per global name -- a duplicate makes lli reject the
        # module outright ("redefinition of global").
        my %seen;
        $seen{$1}++ while $ll =~ /^(\@[\w.]+) = /gm;
        my @dupes = grep { $seen{$_} > 1 } sort keys %seen;
        is_deeply \@dupes, [], "no duplicate globals with: $decl"
            or diag "duplicated: @dupes";
    }
};

done_testing;
