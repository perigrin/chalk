package A; sub m { "A" } package B; sub m { "B" } sub n { "Bn" } package C; our @ISA = ("A", "B"); package main; print C->m, C->n, C->can("n")->(), "\n";
