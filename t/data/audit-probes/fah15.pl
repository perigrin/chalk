package C; our $x=1; sub m1 { $x=2; $_[1] } package main; print C->m1($C::x),"\n";
