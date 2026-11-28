eval { my @a = (1) x -1; my $v = $a[0]; die "end\n" }; print $@;
