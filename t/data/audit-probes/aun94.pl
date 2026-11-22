our $g=1; sub t { local $g = 2; die "x\n" if $_[0]; 7 } my $v = eval { t(0) + t(1) }; print "$g ", defined $v ? $v : "u", "\n";
