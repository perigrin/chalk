# ABOUTME: The four closure-capture node types load from the wire and keep their identity.
# ABOUTME: A capture is a shared mutable cell, so MakeCell must be per-call, never hash-consed.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::IR::Serialize::JSON;

# A CAPTURE IS NOT A VALUE ON AN EDGE. Measured against perl 5.42.0 by the
# producer, and the reason the whole design exists:
#
#   my $n = 5; my $c = sub { $n }; $n = 99;   $c->() is 99   -- the VARIABLE
#   my $n = 5; my $set = sub { $n = shift };  writes reach the outer scope
#   $inc and $rd over one $c                  share ONE cell
#
# so a capture is a heap cell with its own identity, shared by the enclosing
# scope and every closure over it, mutable through any of them. Putting the
# VALUE on AnonSub's inputs would give each closure a snapshot -- correct for
# the read-only case and silently wrong for the other three.
#
# THIS FILE PINS THE LOADER HALF ONLY: the four ops deserialize, carry their
# fields, and hash the way their identity requires. Behaviour is pinned
# separately, end to end, by a-captured-cell-runs.t.
#
# WHY IDENTITY IS THE LOAD-BEARING PART HERE. `for my $i (1..3) { push @subs,
# sub { $i } }` has ONE MakeCell node that executes THREE times and must yield
# three distinct cells. If MakeCell hash-consed, two textually identical
# allocations would collapse into one and every closure would share a cell that
# perl gives them separately -- printing 3,3,3 where perl prints 1,2,3. That is
# the exact defect ArrayRef already hit (019eb6ff item 4: "`[1,2]` and `[1,2]`
# are two distinct arrays, so hash-consing them made one malloc that two
# 'distinct' refs silently aliased").

# from_json is a plain sub that DIES on a bad document rather than
# returning an error, so wrap it: a refusal must fail this test loudly, not
# abort the file before any assertion runs.
sub load ($json) {
    my $g = eval { Chalk::IR::Serialize::JSON::from_json($json) };
    return ($g, $@);
}

# A minimal document exercising all four ops: an outer scope that allocates a
# cell and hands it to a closure, and a body that reads and writes through it.
my $WIRE = <<'JSON';
{
  "methods" : {
    "main::__PROGRAM__" : {
      "nodes" : [
        {
          "id" : 0,
          "inputs" : [],
          "op" : "Start"
        },
        {
          "id" : 1,
          "inputs" : [],
          "op" : "MemStart"
        },
        {
          "fields" : {
            "const_type" : "integer",
            "value" : "5"
          },
          "id" : 2,
          "inputs" : [],
          "op" : "Constant",
          "stamp" : "Int"
        },
        {
          "fields" : {
            "captured_written" : true,
            "cell_name" : "$n"
          },
          "id" : 3,
          "inputs" : [
            2
          ],
          "mem_in" : 1,
          "op" : "MakeCell",
          "stamp" : "Int"
        },
        {
          "fields" : {
            "name" : "main::__PROGRAM__::__ANON__:2:1"
          },
          "id" : 4,
          "inputs" : [
            3
          ],
          "op" : "AnonSub",
          "stamp" : "CodeRef"
        },
        {
          "fields" : {
            "dispatch_kind" : "direct",
            "name" : "main::__PROGRAM__::__ANON__:2:1"
          },
          "id" : 5,
          "inputs" : [
            4
          ],
          "op" : "Call",
          "stamp" : "Int"
        },
        {
          "control_in" : 0,
          "id" : 6,
          "inputs" : [
            5
          ],
          "mem_in" : 1,
          "op" : "Return"
        }
      ],
      "returns" : [
        6
      ],
      "start" : 0
    },
    "main::__PROGRAM__::__ANON__:2:1" : {
      "nodes" : [
        {
          "id" : 0,
          "inputs" : [],
          "op" : "Start"
        },
        {
          "id" : 1,
          "inputs" : [],
          "op" : "MemStart"
        },
        {
          "fields" : {
            "index" : 0,
            "name" : "$n"
          },
          "id" : 2,
          "inputs" : [],
          "op" : "CellParam",
          "stamp" : "Int"
        },
        {
          "fields" : {
            "const_type" : "integer",
            "value" : "1"
          },
          "id" : 3,
          "inputs" : [],
          "op" : "Constant",
          "stamp" : "Int"
        },
        {
          "id" : 4,
          "inputs" : [
            2,
            3
          ],
          "mem_in" : 1,
          "op" : "CellWrite",
          "stamp" : "Int"
        },
        {
          "id" : 5,
          "inputs" : [
            2
          ],
          "mem_in" : 4,
          "op" : "CellRead",
          "stamp" : "Int"
        },
        {
          "control_in" : 0,
          "id" : 6,
          "inputs" : [
            5
          ],
          "mem_in" : 1,
          "op" : "Return"
        }
      ],
      "returns" : [
        6
      ],
      "start" : 0
    }
  },
  "version" : 2, "writer" : "chalk"
}
JSON

subtest 'the four capture ops deserialize' => sub {
    my ($graphs, $err) = load($WIRE);
    ok !$err, 'the document loads' or do { diag("  $err"); return };

    my %op;
    for my $gname (keys %$graphs) {
        $op{ $_->operation }++ for $graphs->{$gname}->nodes->@*;
    }

    # ASSERTED POSITIVELY, one op at a time. "no unknown ops" would be
    # satisfied by a loader that silently dropped all four.
    ok $op{MakeCell},  'MakeCell survives the round trip';
    ok $op{CellRead},  'CellRead survives';
    ok $op{CellWrite}, 'CellWrite survives';
    ok $op{CellParam}, 'CellParam survives';
};

subtest 'a cell carries the fields the backend needs' => sub {
    my ($graphs, $err) = load($WIRE);
    ok !$err, 'the document loads' or return;

    my ($cell) = grep { $_->operation eq 'MakeCell' }
                 $graphs->{'main::__PROGRAM__'}->nodes->@*;
    ok $cell, 'the MakeCell node is present' or return;

    is $cell->cell_name, '$n', 'cell_name rides the wire';
    # `captured_written` decides whether the cell can be elided to a plain
    # value. Getting it wrong in the false direction is a MISCOMPILE (a write
    # that no reader observes), so the loader must not invent it.
    ok $cell->captured_written, 'captured_written rides the wire';

    my ($param) = grep { $_->operation eq 'CellParam' }
                  $graphs->{'main::__PROGRAM__::__ANON__:2:1'}->nodes->@*;
    ok $param, 'the CellParam node is present' or return;
    is $param->index, 0, 'the cell arrives at a known position';
};

# THE IDENTITY ASSERTION, and the reason this file exists. Two MakeCell nodes
# with IDENTICAL inputs and fields must stay distinct: they are two allocations,
# and merging them makes one cell where perl has two.
subtest 'two identical MakeCells are two distinct cells' => sub {
    # The SAME allocation twice over the SAME inputs, each handed to its own
    # closure so both stay reachable from the return. Ids stay DENSE: the
    # loader indexes nodes by array position, not by id.
    my $two = <<'JSON';
{
  "methods" : {
    "main::__PROGRAM__" : {
      "nodes" : [
        {
          "id" : 0,
          "inputs" : [],
          "op" : "Start"
        },
        {
          "id" : 1,
          "inputs" : [],
          "op" : "MemStart"
        },
        {
          "fields" : {
            "const_type" : "integer",
            "value" : "5"
          },
          "id" : 2,
          "inputs" : [],
          "op" : "Constant",
          "stamp" : "Int"
        },
        {
          "fields" : {
            "captured_written" : true,
            "cell_name" : "$n"
          },
          "id" : 3,
          "inputs" : [
            2
          ],
          "mem_in" : 1,
          "op" : "MakeCell",
          "stamp" : "Int"
        },
        {
          "fields" : {
            "captured_written" : true,
            "cell_name" : "$n"
          },
          "id" : 4,
          "inputs" : [
            2
          ],
          "mem_in" : 1,
          "op" : "MakeCell",
          "stamp" : "Int"
        },
        {
          "fields" : {
            "name" : "main::__PROGRAM__::__ANON__:2:1"
          },
          "id" : 5,
          "inputs" : [
            3
          ],
          "op" : "AnonSub",
          "stamp" : "CodeRef"
        },
        {
          "fields" : {
            "name" : "main::__PROGRAM__::__ANON__:2:1"
          },
          "id" : 6,
          "inputs" : [
            4
          ],
          "op" : "AnonSub",
          "stamp" : "CodeRef"
        },
        {
          "fields" : {
            "dispatch_kind" : "direct",
            "name" : "main::__PROGRAM__::__ANON__:2:1"
          },
          "id" : 7,
          "inputs" : [
            5
          ],
          "op" : "Call",
          "stamp" : "Int"
        },
        {
          "fields" : {
            "dispatch_kind" : "direct",
            "name" : "main::__PROGRAM__::__ANON__:2:1"
          },
          "id" : 8,
          "inputs" : [
            6
          ],
          "op" : "Call",
          "stamp" : "Int"
        },
        {
          "id" : 9,
          "inputs" : [
            7,
            8
          ],
          "op" : "Add",
          "stamp" : "Int"
        },
        {
          "control_in" : 0,
          "id" : 10,
          "inputs" : [
            9
          ],
          "mem_in" : 1,
          "op" : "Return"
        }
      ],
      "returns" : [
        10
      ],
      "start" : 0
    },
    "main::__PROGRAM__::__ANON__:2:1" : {
      "nodes" : [
        {
          "id" : 0,
          "inputs" : [],
          "op" : "Start"
        },
        {
          "id" : 1,
          "inputs" : [],
          "op" : "MemStart"
        },
        {
          "fields" : {
            "index" : 0,
            "name" : "$n"
          },
          "id" : 2,
          "inputs" : [],
          "op" : "CellParam",
          "stamp" : "Int"
        },
        {
          "fields" : {
            "const_type" : "integer",
            "value" : "1"
          },
          "id" : 3,
          "inputs" : [],
          "op" : "Constant",
          "stamp" : "Int"
        },
        {
          "id" : 4,
          "inputs" : [
            2,
            3
          ],
          "mem_in" : 1,
          "op" : "CellWrite",
          "stamp" : "Int"
        },
        {
          "id" : 5,
          "inputs" : [
            2
          ],
          "mem_in" : 4,
          "op" : "CellRead",
          "stamp" : "Int"
        },
        {
          "control_in" : 0,
          "id" : 6,
          "inputs" : [
            5
          ],
          "mem_in" : 1,
          "op" : "Return"
        }
      ],
      "returns" : [
        6
      ],
      "start" : 0
    }
  },
  "version" : 2, "writer" : "chalk"
}
JSON

    my ($graphs, $err) = load($two);
    ok !$err, 'the two-allocation document loads' or do { diag("  $err"); return };

    my @cells = grep { $_->operation eq 'MakeCell' }
                $graphs->{'main::__PROGRAM__'}->nodes->@*;
    is scalar(@cells), 2, 'BOTH allocations survive -- hash-consing would leave 1'
        or diag('  a capture that collapses here shares a cell perl keeps separate');
};

# THE CONTROL. A per-call identity must not be bought by breaking determinism:
# loading the SAME document twice must produce the same hashes, or codegen stops
# being byte-identical. This is the defect AnonSub's own comment records for its
# old process-global anon_id counter.
subtest 'loading the same document twice is stable' => sub {
    my ($g1, $e1) = load($WIRE);
    my ($g2, $e2) = load($WIRE);
    ok !$e1 && !$e2, 'both loads succeed' or return;

    my $h = sub ($g) {
        join '|', sort map { $_->content_hash }
                  grep { $_->operation =~ /^(MakeCell|CellRead|CellWrite|CellParam)$/ }
                  map { $g->{$_}->nodes->@* } sort keys %$g;
    };
    is $h->($g2), $h->($g1),
        'the capture nodes hash identically across two loads';
};

done_testing;
