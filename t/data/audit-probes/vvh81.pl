my $s = join ",", "a", eval { die "x\n" }, "b"; print "$s\n";
