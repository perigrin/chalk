package A; sub m { $_[1] = "A" } package B; sub m { 1 } package main; my $x = "o"; for my $c (qw(B A)) { $c->m($x) } print "$x\n";
