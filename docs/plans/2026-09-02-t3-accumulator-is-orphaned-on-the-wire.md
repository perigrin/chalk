# ABOUTME: T3's loop accumulator never reaches its Print -- the defect is on the wire.
# ABOUTME: The producer builds the `$s +=` Add and wires it to nothing; there is no Phi for $s.

# T3: the loop accumulator is orphaned by the producer

Corpus case `control-flow.md` "T3 cond_expr inside a loop body (t/base blocker:
translate.t)". Behaviour leg: **lli prints `0`, perl prints `12`** -- a SILENT
WRONG ANSWER, not a refusal, which makes it the most dangerous class in the
worklist.

    use 5.42.0;
    my $i = 0;
    my $s = 0;
    while ($i < 3) { $s += ($i > 1 ? 10 : 1); $i++ }
    say($s);

## It is NOT the loader

Measured against pinned producer bc9b285. The producer emits 20 nodes; the
loader retains 10. That looked like a loader drop, and it is not -- the ten it
drops are ALREADY UNREACHABLE on the wire.

Full wire connectivity for `main::__PROGRAM__`:

      #0   Start         <- []
      #1   Constant      <- []                      stamp=Undef
      #2   Constant      <- []                      stamp=Int      <- `my $s = 0`
      #3   Coerce        <- [Constant#2]            stamp=Str
      #4   Constant      <- []                      stamp=Str
      #5   Loop          <- [Start#0]               control_in=0
      #6   Proj          <- [Loop#5]
      #7   Region        <- [Proj#6]
      #8   Print         <- [Coerce#3,Constant#4]   control_in=7
      #9   Return        <- [Constant#1]            control_in=8
      #10  Phi           <- [Constant#2,Add#15]     stamp=Int      <- $i ONLY
      #11  Constant      <- []                      stamp=Int
      #12  NumLt         <- [Phi#10,Constant#11]    control_in=5
      #13  Proj          <- [Loop#5]
      #14  Constant      <- []                      stamp=Int
      #15  Add           <- [Phi#10,Constant#14]    stamp=Int      <- `$i++`
      #16  NumGt         <- [Phi#10,Constant#14]    stamp=Boolean
      #17  Constant      <- []                      stamp=Int
      #18  TernaryExpr   <- [NumGt#16,Const#17,Const#14]  stamp=Int
      #19  Add           <- [Constant#2,Ternary#18] stamp=Int      <- `$s += ...`

Consumer check:

      #19  Add          consumed by: ** NOTHING **
      #18  TernaryExpr  consumed by: ['Add#19']
      #10  Phi          consumed by: ['NumLt#12', 'Add#15', 'NumGt#16']

## Two defects, both upstream

1. **THERE IS NO PHI FOR `$s`.** The only Phi (#10) is the loop counter `$i`
   -- its inputs are `Constant#2` (the init) and `Add#15` (`$i++`), and its
   consumers are the condition, the increment, and the ternary guard. `$s`
   crosses the back edge too and has no merge node at all.

2. **THE ACCUMULATE IS ORPHANED.** `Add#19` computes `$s + (ternary)` reading
   the INITIAL `Constant#2` rather than a loop-carried value, and nothing
   consumes it. It is dead the moment it is built.

The consequence is visible in `Print#8`: it reads `Coerce#3 <- Constant#2`,
the pre-loop `$s = 0`. So the emitted program faithfully prints the initial
value, and the loop body computes a result no one reads. `0` is exactly what
this graph MEANS; the graph is the wrong graph.

## Why the corpus spec did not catch it earlier

The shape leg reports `missing [Constant(1) :Int, Constant(10) :Int, Phi :Int,
Add :Int, TernaryExpr :Int, NumGt :Boolean, Phi :Int, Add :Int]` -- note it
asks for **TWO** Phis and two Adds. The spec is right and always was: one Phi
for `$i`, one for `$s`. The wire ships one.

## Owner

perl5-son. The loader cannot repair this -- a missing merge node is not a
typing gap, and inventing a Phi here would be the loader guessing at control
flow the producer did not express. Chalk's side is already correct: the
`missing` list names precisely the two nodes that are absent.
