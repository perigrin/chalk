# ABOUTME: Scope-fence audit for the IR-node-unification milestone (i5, capstone).
# ABOUTME: asserts the 10 named MOP/repr-inference subs in JSON.pm are byte-identical to the milestone base.

use 5.42.0;
use utf8;
use Test::More;

use File::Spec;

# The milestone-base fixture is a committed snapshot of
# lib/Chalk/IR/Serialize/JSON.pm as of commit 1ee5ec9f (the last commit
# before the IR-node-unification Steps 1-4 began touching this file). It is
# captured as a file rather than shelled out to `git show` at test time so
# the audit does not depend on the base commit remaining reachable in this
# checkout's history.
my $current_path = 'lib/Chalk/IR/Serialize/JSON.pm';
my $base_path     = File::Spec->catfile(qw(t bootstrap fixtures mop-fence-base.pm));

# The 10 fenced subs: repr/MOP inference and class replay. Steps 1-4 of the
# unification milestone were scoped to control/wire/topo handling
# (_extract_fields, _all_nodes_topo, _serialize_graph, _deserialize_graph)
# and were never supposed to touch these -- this test is the fence.
my @FENCED_SUBS = qw(
    _replay_classes
    _seed_and_propagate_reprs
    _propagate_computed_reprs
    _infer_param_field_types
    _infer_field_types_from_stores
    _stamp_field_access_reprs
    _stamp_method_call_reprs
    _ctor_arg_reprs
    _control_chain_nodes
    _classes_in_parent_order
);

# extract_sub($file_lines, $name) -- pull the exact text of a top-level sub
# out of a JSON.pm-shaped file, from its `sub NAME (...)  {` line up to (but
# not including) the next top-level `sub ` declaration, or EOF. Every
# top-level sub in this file starts at column 0 (`^sub `), including the
# ones with an inner closure (`_classes_in_parent_order`'s `$place = sub
# ($name) {...}` is indented, not at column 0), so a plain anchored-line
# scan is a reliable boundary -- no brace-balancing needed.
sub extract_sub {
    my ($lines, $name) = @_;
    my $start;
    for my $i (0 .. $#$lines) {
        if ($lines->[$i] =~ /^sub \Q$name\E\b/) {
            $start = $i;
            last;
        }
    }
    return undef unless defined $start;

    my $end = $#$lines;
    for my $i ($start + 1 .. $#$lines) {
        if ($lines->[$i] =~ /^sub \s*\w/) {
            $end = $i - 1;
            last;
        }
    }
    return join('', @{$lines}[$start .. $end]);
}

sub read_lines {
    my ($path) = @_;
    open my $fh, '<', $path or die "cannot open $path: $!";
    my @lines = <$fh>;
    close $fh;
    return \@lines;
}

ok(-e $current_path, "current file exists: $current_path");
ok(-e $base_path, "milestone-base fixture exists: $base_path");

my $current_lines = read_lines($current_path);
my $base_lines    = read_lines($base_path);

for my $name (@FENCED_SUBS) {
    my $current_body = extract_sub($current_lines, $name);
    my $base_body     = extract_sub($base_lines, $name);

    ok(defined $current_body, "found $name in current JSON.pm");
    ok(defined $base_body, "found $name in milestone-base fixture");
    next unless defined $current_body && defined $base_body;

    # Non-vacuous: prove the extractor pulled a real body, not an empty match.
    ok(length($current_body) > 20, "$name: extracted a non-trivial body (" . length($current_body) . " bytes)");

    is($current_body, $base_body, "$name is byte-identical to the milestone base (fenced -- must not change)");
}

done_testing();
