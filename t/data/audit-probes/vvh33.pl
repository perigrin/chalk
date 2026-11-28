eval { die "x\n" }; my $v = eval { $@ }; print $v eq "" ? "empty" : "kept", "\n";
