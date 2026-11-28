sub t { die "obj\n" } my $v = eval { t(); 1 } // "undef"; print "$v\n";
