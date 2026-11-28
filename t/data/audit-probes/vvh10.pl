my $x = 1; sub t { die "z\n" if $_[0]; $x = 2 } eval { t(0); t(1); $x = 3 }; print "$x$@";
