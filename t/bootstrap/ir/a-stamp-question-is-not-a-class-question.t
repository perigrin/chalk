#!/usr/bin/env perl
# ABOUTME: No stamp read may be gated on `isa Chalk::IR::Value` -- stamp lives on Node.
# ABOUTME: Guards the class of bug that made 0cc04737 a miscompile, twice.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::IR::Node;
use Chalk::IR::Value;

# ---------------------------------------------------------------------------
# THE BUG THIS EXISTS TO PREVENT, WHICH HAS SHIPPED TWICE
#
# `stamp` is declared on Chalk::IR::Node (Node.pm:64) -- the BASE. Every node
# carries one. But Chalk::IR::Value is a SIBLING of the value-producing control
# nodes rather than their parent: Print, Proj, VarDecl and ListAssign are each
# `:isa(Chalk::IR::Node)` DIRECTLY.
#
# So `$node isa Chalk::IR::Value` asks about the CLASS HIERARCHY when the
# question is about the STAMP, and silently answers "no stamp" for four node
# kinds that have one.
#
#   0cc04737  a coercion guard read the class instead of the stamp; the wire's
#             stale `Scalar` won for a Print and lli refused the module
#             ("'%tmp_10' defined with type 'i1' but expected '%Slot'").
#
#   a404a718  the corpus harness gated a spec-declared `:Repr` the same way and
#             SILENTLY DROPPED it for VarDecl. The failure surfaced three steps
#             later as "VarDecl reached LLVM backend with NO representation --
#             fix TypeInference", naming the wrong pass entirely.
#
# The second one landed because the first was fixed at its site rather than as
# a class. This test is the class.
# ---------------------------------------------------------------------------

my @SIBLINGS = qw(Print Proj VarDecl ListAssign);

subtest 'the premise: stamp is on Node, and these four are not Values' => sub {
    # If this subtest ever fails, the rest of the file is measuring nothing --
    # either the hierarchy changed or the field moved, and the guards below
    # need rethinking rather than mechanical updating.
    ok(Chalk::IR::Node->can('stamp'),     'stamp is declared on Chalk::IR::Node');
    ok(Chalk::IR::Node->can('set_stamp'), 'set_stamp is declared on Chalk::IR::Node');

    for my $c (@SIBLINGS) {
        my $pkg = "Chalk::IR::Node::$c";
        eval "require $pkg; 1" or do { fail("$pkg loads"); next };
        ok(!$pkg->isa('Chalk::IR::Value'),
            "$c is NOT a Chalk::IR::Value -- so a Value test would skip it");
        ok($pkg->isa('Chalk::IR::Node'),
            "$c IS a Chalk::IR::Node -- so it carries a stamp");
    }
};

subtest 'no source line gates a stamp read on isa Chalk::IR::Value' => sub {
    # A textual check, because the defect is textual: the guard and the read
    # sit on the same line, and the pattern is what makes it wrong.
    #
    # It scans lib/ AND t/lib/ -- the second occurrence was in the harness, and
    # a check that only looked at lib/ would have missed it.
    my @offenders;
    for my $root ('lib', 't/lib') {
        my @files;
        my $walk;
        $walk = sub {
            my ($dir) = @_;
            opendir(my $dh, $dir) or return;
            for my $e (sort readdir $dh) {
                next if $e eq '.' || $e eq '..';
                my $path = "$dir/$e";
                if    (-d $path)            { $walk->($path) }
                elsif ($path =~ /\.pm\z/)   { push @files, $path }
            }
            closedir $dh;
        };
        $walk->($root);

        for my $f (@files) {
            open my $fh, '<', $f or next;
            my $n = 0;
            while (my $line = <$fh>) {
                $n++;
                next if $line =~ /^\s*#/;                  # a comment may DESCRIBE it
                next unless $line =~ /isa\s+Chalk::IR::Value/;
                next unless $line =~ /->\s*(?:set_)?stamp\b/;
                push @offenders, "$f:$n";
            }
            close $fh;
        }
    }

    is_deeply(\@offenders, [],
        'no line both tests `isa Chalk::IR::Value` and reads a stamp')
        or diag("gate the read on `isa Chalk::IR::Node` instead -- these four "
              . "node kinds carry a stamp without being Values:\n  "
              . join("\n  ", @offenders));
};

done_testing;
