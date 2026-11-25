my @v = (1, "a", undef, "", 0); print join("", map { defined $_ ? "d" : "u" } @v), join("", map { length($_ // "") } @v), "\n";
