sub d { die "boom\n" } my $r = eval { d(); 1 }; print defined $r ? "ok" : "caught: $@";
