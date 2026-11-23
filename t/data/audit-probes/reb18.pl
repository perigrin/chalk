my $ok = eval { die "a\n"; 1 }; print defined $ok ? "d":"u", " $@";
