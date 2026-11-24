my @r = eval { sort { die "s\n" } 2,1 }; print scalar(@r), $@;
