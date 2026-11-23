my $i=0; eval { while (1) { $i++; die "stop\n" if $i>3 } }; print "$i $@";
