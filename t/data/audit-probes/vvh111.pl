my $s = "a"; sub d { die "x\n" } eval { $s .= "b" . d() }; print "$s\n";
