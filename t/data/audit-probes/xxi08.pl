my $x = 1; eval '$x = 2; die "s\n"'; print "$x$@";
