package C; sub new { bless {}, shift } sub m { shift; "@_" } package main; my $x=1; print C->new->m($x, $x++), "\n";
