my $ok = eval { die "z\n"; 1 }; print $ok ? "ok" : "fail", "\n";
