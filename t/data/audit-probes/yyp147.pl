package C; sub m { shift; "@_" } package main; our $g=1; print C->m($g, $g++), "\n";
