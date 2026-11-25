my @n = (3, "3", 3.0, "3.0", "3abc"); { no warnings; print join(",", map { $_ + 0 } @n), " ", join(",", map { "$_" } @n), "\n"; }
