package C; sub new { bless {}, shift } sub m { shift; "@_" } package main; our $g=1; print C->new->m($g, $g++), "\n";
