my $t = time; select(undef, undef, undef, 1.1); my $d = time - $t; print $d >= 1 ? "slept\n" : "no sleep\n";
