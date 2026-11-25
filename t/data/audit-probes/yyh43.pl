my @e; my %e; print scalar(@e), @e ? "t" : "f", %e ? "t" : "f", scalar(keys %e), defined $e[0] ? "d" : "u", "[@e]", "\n";
