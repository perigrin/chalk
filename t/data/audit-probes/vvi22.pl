my @l = ("a\n", "b\n"); chomp(my @m = @l); print length($l[0]), length($m[0]), "\n";
