sub h { return } sub u { return undef } my @a = h(); my @b = u(); my %m = (a => h(), b => 2); print scalar(@a), scalar(@b), join(",", map { $_ // "u" } %m{a}), "\n";
