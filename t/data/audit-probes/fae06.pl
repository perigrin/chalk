my $ok = eval { die "a\n"; 1 }; print $ok ? "y":"n", "\n";
