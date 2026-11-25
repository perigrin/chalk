use Symbol qw(gensym qualify); my $s = gensym; my $t = gensym; print ref($s), $s == $t ? "same" : "diff", " ", qualify("x"), " ", qualify("x", "P"), " ", qualify("P::x"), "\n";
