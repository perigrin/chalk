my @a=(1); my $v = eval { $a[0]->method }; print $@ ? "e" : "n", "\n";
