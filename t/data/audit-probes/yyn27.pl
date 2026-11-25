sub risky { die "bad\n" if $_[0]; "fine" } my @res = map { eval { risky($_) } // "E" } (0, 1, 0); print "@res\n";
