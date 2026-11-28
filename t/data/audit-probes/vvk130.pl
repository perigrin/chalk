package B1; sub new { bless {v => 1}, shift } sub v { $_[0]{v} } sub dbl { $_[0]->v * 2 } package D1; our @ISA = ("B1"); sub v { 5 } package main; print B1->new->dbl, D1->new->dbl, "\n";
