our $n = 0; sub one { $n = $n + 1 } sub two { one(); one() } for (1..2) { two(); $n += 100 } print "$n\n";
