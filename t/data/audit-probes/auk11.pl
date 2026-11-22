my $ok = eval { for my $x (1) { die "m\n" } 1 }; print $ok ? "ok" : "died", "\n";
