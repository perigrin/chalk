$_ = "o"; for (1..2) { } print; for my $x (1) { $_ = "i" } print; print map({ $_ } 1), $_, "\n";
