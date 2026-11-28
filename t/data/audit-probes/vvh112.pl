my $s = "a"; sub d { $s .= "c"; die "x\n" } eval { $s .= "b" . d() }; print "$s\n";
