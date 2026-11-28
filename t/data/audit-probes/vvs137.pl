sub f { return } my $s = join(",", "a", f(), "b"); print "$s\n";
