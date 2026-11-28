my $s = "abc"; my $t = ucfirst(lc("HELLO")) . uc(substr($s, 0, 1)) . lc("X") x 2; print "$t\n";
