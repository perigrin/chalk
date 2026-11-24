sub t { eval { die "t\n" }; return "r" } eval { die "o\n" }; my $v=t(); print "$v [$@]\n";
