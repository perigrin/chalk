my $ok = eval { my @a = map { die "m\n" } 1; 1 }; print defined $ok ? "ok" : "died", "\n";
